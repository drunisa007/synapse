"""Council orchestrator — coordinates stages, publishes events, persists results."""

from __future__ import annotations

import asyncio
import hashlib
import logging
import time
import uuid
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sqlalchemy.ext.asyncio import AsyncSession

from synapse.audit import emit as audit_emit
from synapse.council.conflict import check_conflict
from synapse.council.convergence import check_convergence
from synapse.council.models import (
    CouncilMember,
    CouncilResult,
    CouncilReviewRequest,
    DeliberationRound,
    MemberCritique,
    StageOneResponse,
)
from synapse.council.stages.critique import run_critique
from synapse.council.stages.gather import run_gather
from synapse.council.stages.rank import run_rank
from synapse.council.stages.red_team import run_red_team
from synapse.council.stages.revise import run_revise
from synapse.council.stages.synthesise import run_synthesise
from synapse.council.thread import append_event, get_thread_by_council
from synapse.db.models import CouncilSession, CouncilStatus, CouncilTranscript, ThreadEventType
from synapse.llm.client import LLMClient
from synapse.memory.banks import Banks, council_tags, verdict_tags
from synapse.memory.context import AstrocyteContext

if TYPE_CHECKING:
    from synapse.memory.gateway_client import AstrocyteGatewayClient, MemoryHit
    from synapse.realtime.centrifugo import CentrifugoClient

_logger = logging.getLogger(__name__)


class CouncilOrchestrator:
    def __init__(
        self,
        astrocyte: AstrocyteGatewayClient,
        centrifugo: CentrifugoClient,
        llm: LLMClient,
        settings,
        http_client=None,
        notification_dispatcher=None,
    ) -> None:
        self._astrocyte = astrocyte
        self._centrifugo = centrifugo
        self._llm = llm
        self._settings = settings
        self._http_client = http_client
        self._notification_dispatcher = notification_dispatcher

    async def run(
        self,
        session_id: uuid.UUID,
        question: str,
        members: list[CouncilMember],
        chairman: CouncilMember,
        context: AstrocyteContext,
        db: AsyncSession,
        council_type: str = "llm",
        topic_tag: str | None = None,
        human_turns: list[str] | None = None,
        council_review: CouncilReviewRequest | None = None,
    ) -> CouncilResult | None:
        """Run the full council pipeline.

        Returns None for async councils that park in ``waiting_contributions``
        — they are resumed later via :meth:`resume` once quorum is met.

        Args:
            human_turns: Mode 2 messages injected by a human participant during
                deliberation. Included verbatim in the transcript retained to the
                ``councils`` Astrocyte bank so future councils can recall not just
                what agents said but also the human context that shaped the session.
        """
        council_id = str(session_id)

        async def publish(event_type: str, payload: dict) -> None:
            try:
                await self._centrifugo.publish_council_event(council_id, event_type, payload)
            except Exception as e:
                _logger.warning("Centrifugo publish failed (%s): %s", event_type, e)

        async def set_status(status: str) -> None:
            session = await db.get(CouncilSession, session_id)
            if session:
                session.status = status
                await db.commit()

        # --- Recall precedents ---
        await set_status(CouncilStatus.pending)
        precedents: list[MemoryHit] = []
        recall_started_at = time.perf_counter()
        try:
            recall_tags = self._council_review_memory_tags(council_review)
            precedents = await self._astrocyte.recall(
                query=self._council_review_memory_query(question, council_review),
                bank_id=Banks.PRECEDENTS,
                context=context,
                max_results=self._settings.max_precedents,
                tags=recall_tags,
            )
            if recall_tags and not precedents:
                precedents = await self._astrocyte.recall(
                    query=self._council_review_memory_query(question, council_review),
                    bank_id=Banks.PRECEDENTS,
                    context=context,
                    max_results=self._settings.max_precedents,
                )
            self._log_observation(
                "synapse.council.memory_recall",
                request_id=self._observation_request_id(council_review, context),
                council_id=council_id,
                latency_seconds=time.perf_counter() - recall_started_at,
                verdict_status="context_ready",
            )
        except Exception as e:
            self._log_observation(
                "synapse.council.memory_recall",
                request_id=self._observation_request_id(council_review, context),
                council_id=council_id,
                latency_seconds=time.perf_counter() - recall_started_at,
                verdict_status="context_unavailable",
                failure_reason=type(e).__name__,
                level=logging.WARNING,
            )

        await publish("precedents_ready", {"count": len(precedents)})

        # --- Stage 1: Gather ---
        await set_status(CouncilStatus.stage_1)
        await publish("stage_started", {"stage": 1})

        # B3 — async councils: LLM members respond immediately; human members
        # contribute later via POST /v1/councils/{id}/contribute.
        if council_type == "async":
            return await self._run_async_stage1(
                session_id=session_id,
                question=question,
                members=members,
                chairman=chairman,
                precedents=precedents,
                context=context,
                db=db,
                council_type=council_type,
                topic_tag=topic_tag,
                human_turns=human_turns or [],
                publish=publish,
                council_review=council_review,
            )

        stage1_responses = await run_gather(
            members=members,
            question=question,
            precedents=precedents,
            llm=self._llm,
            timeout=self._settings.stage1_timeout_seconds,
        )

        await publish(
            "stage1_complete",
            {
                "responses": [
                    {"member_id": r.member_id, "member_name": r.member_name, "content": r.content}
                    for r in stage1_responses
                ],
            },
        )

        # --- Multi-round deliberation (B5) ---
        current_responses = stage1_responses
        deliberation_rounds: list = []

        is_red_team = council_type == "red_team"
        do_deliberation = (
            self._settings.deliberation_enabled
            and len(current_responses) > 1
            and council_type not in ("solo",)
        )

        if is_red_team:
            # Red team: one round of adversarial attacks, no revise phase
            await publish("red_team_started", {})
            attacks = await run_red_team(
                members=members,
                question=question,
                stage1_responses=current_responses,
                llm=self._llm,
                timeout=self._settings.critique_timeout_seconds,
            )
            deliberation_rounds.append(
                {
                    "round": 1,
                    "mode": "red_team",
                    "attacks": [a.model_dump() for a in attacks],
                    "converged": False,
                }
            )
            await publish(
                "red_team_complete",
                {
                    "attacks": [
                        {"member_id": a.member_id, "member_name": a.member_name} for a in attacks
                    ],
                },
            )

        elif do_deliberation:
            max_rounds = self._settings.max_deliberation_rounds
            threshold = self._settings.convergence_threshold

            for round_num in range(1, max_rounds + 1):
                await publish("deliberation_round_started", {"round": round_num})

                # Critique phase
                critiques = await run_critique(
                    members=members,
                    question=question,
                    current_responses=current_responses,
                    llm=self._llm,
                    timeout=self._settings.critique_timeout_seconds,
                )

                # Revise phase
                revised = await run_revise(
                    members=members,
                    question=question,
                    current_responses=current_responses,
                    critiques=critiques,
                    llm=self._llm,
                    timeout=self._settings.revise_timeout_seconds,
                )

                converged = check_convergence(current_responses, revised, threshold)
                current_responses = revised

                deliberation_rounds.append(
                    {
                        "round": round_num,
                        "mode": "deliberation",
                        "critiques": [c.model_dump() for c in critiques],
                        "revised_responses": [r.model_dump() for r in revised],
                        "converged": converged,
                    }
                )

                await publish(
                    "deliberation_round_complete",
                    {
                        "round": round_num,
                        "converged": converged,
                        "revised_count": len(revised),
                    },
                )

                if converged:
                    _logger.info("Council %s converged after round %d", council_id, round_num)
                    break

        # Use the latest (possibly revised) responses for ranking
        final_responses = current_responses

        return await self._complete_council(
            session_id=session_id,
            question=question,
            members=members,
            chairman=chairman,
            stage1_responses=final_responses,
            precedents=precedents,
            council_type=council_type,
            topic_tag=topic_tag,
            context=context,
            db=db,
            deliberation_rounds=deliberation_rounds,
            human_turns=human_turns or [],
            publish=publish,
            set_status=set_status,
            council_review=council_review,
        )

    # ---------------------------------------------------------------------------
    # B3 — Async stage 1 helper
    # ---------------------------------------------------------------------------

    async def _run_async_stage1(
        self,
        *,
        session_id: uuid.UUID,
        question: str,
        members: list[CouncilMember],
        chairman: CouncilMember,
        precedents: list,
        context: AstrocyteContext,
        db: AsyncSession,
        council_type: str,
        topic_tag: str | None,
        human_turns: list[str],
        publish,
        council_review: CouncilReviewRequest | None = None,
    ) -> CouncilResult | None:
        """Stage 1 for async councils.

        LLM members respond immediately; human members contribute later via
        ``POST /v1/councils/{id}/contribute``.  Returns the completed
        ``CouncilResult`` if quorum is already met (all-LLM council), otherwise
        parks the session in ``waiting_contributions`` and returns ``None``.
        """
        council_id = str(session_id)

        async def set_status(status: str) -> None:
            session = await db.get(CouncilSession, session_id)
            if session:
                session.status = status
                await db.commit()

        llm_members = [m for m in members if m.member_type == "llm"]
        human_members = [m for m in members if m.member_type == "human"]

        # Gather LLM member responses immediately
        llm_responses: list[StageOneResponse] = []
        if llm_members:
            llm_responses = await run_gather(
                members=llm_members,
                question=question,
                precedents=precedents,
                llm=self._llm,
                timeout=self._settings.stage1_timeout_seconds,
            )

        # Save LLM responses as contributions to the session
        session = await db.get(CouncilSession, session_id)
        if session:
            new_contributions = [
                {
                    "member_id": r.member_id,
                    "member_name": r.member_name,
                    "content": r.content,
                    "member_type": "llm",
                    "submitted_at": datetime.now(UTC).isoformat(),
                }
                for r in llm_responses
                if not r.error
            ]
            session.contributions = [*session.contributions, *new_contributions]
            await db.commit()
            await db.refresh(session)

        await publish(
            "stage1_partial",
            {
                "llm_responses": len(llm_responses),
                "human_pending": len(human_members),
            },
        )

        # Check if quorum already met (e.g. no human members)
        session = await db.get(CouncilSession, session_id)
        if session:
            from synapse.council.session import quorum_met

            if quorum_met(session):
                _logger.info(
                    "Council %s: quorum met immediately (%d contributions)",
                    council_id,
                    len(session.contributions),
                )
                return await self._complete_council(
                    session_id=session_id,
                    question=question,
                    members=members,
                    chairman=chairman,
                    stage1_responses=llm_responses,
                    precedents=precedents,
                    council_type=council_type,
                    topic_tag=topic_tag,
                    context=context,
                    db=db,
                    deliberation_rounds=[],
                    human_turns=human_turns,
                    publish=publish,
                    set_status=set_status,
                    council_review=council_review,
                )

        # Quorum not yet met — park and wait for human contributions
        await set_status(CouncilStatus.waiting_contributions)
        effective_quorum = (session.quorum if session else None) or len(members)
        await publish(
            "waiting_contributions",
            {
                "session_id": council_id,
                "quorum": effective_quorum,
                "received": len(session.contributions) if session else len(llm_responses),
                "deadline": (
                    session.contribution_deadline.isoformat()
                    if session and session.contribution_deadline
                    else None
                ),
            },
        )
        _logger.info(
            "Council %s waiting for contributions (%d/%d)",
            council_id,
            len(session.contributions) if session else 0,
            effective_quorum,
        )

        # --- Fire waiting_contributions webhook (B9) ---
        if self._http_client:
            try:
                from synapse.webhooks.delivery import fire_webhooks

                asyncio.create_task(
                    fire_webhooks(
                        db,
                        self._http_client,
                        "waiting_contributions",
                        {
                            "council_id": council_id,
                            "quorum": effective_quorum,
                            "received": len(session.contributions) if session else 0,
                        },
                        context.tenant_id,
                    )
                )
            except Exception as _wh_err:
                _logger.warning("Webhook firing failed (waiting_contributions): %s", _wh_err)

        return None

    # ---------------------------------------------------------------------------
    # B3 — Resume from waiting_contributions
    # ---------------------------------------------------------------------------

    async def resume(self, session_id: uuid.UUID, db: AsyncSession) -> CouncilResult | None:
        """Resume an async council after quorum is met.

        Loads contributions from the session, reconstructs members/chairman/context
        from DB, re-recalls precedents, and runs Stage 2+3.  Called by:
        - ``POST /v1/councils/{id}/contribute`` when quorum is detected
        - The scheduler when ``contribution_deadline`` is reached (B7)
        """
        session = await db.get(CouncilSession, session_id)
        if not session:
            _logger.warning("resume: session %s not found", session_id)
            return None
        if session.status != CouncilStatus.waiting_contributions:
            _logger.warning(
                "resume: session %s has status %s, expected waiting_contributions",
                session_id,
                session.status,
            )
            return None

        council_id = str(session_id)

        async def publish(event_type: str, payload: dict) -> None:
            try:
                await self._centrifugo.publish_council_event(council_id, event_type, payload)
            except Exception as e:
                _logger.warning("Centrifugo publish failed (%s): %s", event_type, e)

        async def set_status(status: str) -> None:
            s = await db.get(CouncilSession, session_id)
            if s:
                s.status = status
                await db.commit()

        # Reconstruct from DB
        members = [CouncilMember(**m) for m in session.members]
        chairman = CouncilMember(**session.chairman)
        council_review = self._council_review_from_session(session)
        context = AstrocyteContext(
            principal=session.created_by,
            tenant_id=session.tenant_id,
            request_id=council_review.request_id if council_review else None,
        )

        stage1_responses = [
            StageOneResponse(
                member_id=c["member_id"],
                member_name=c["member_name"],
                content=c["content"],
            )
            for c in session.contributions
        ]

        # Re-recall precedents (original ones were not persisted yet)
        precedents: list = []
        recall_started_at = time.perf_counter()
        try:
            precedents = await self._astrocyte.recall(
                query=self._council_review_memory_query(session.question, council_review),
                bank_id=Banks.PRECEDENTS,
                context=context,
                max_results=self._settings.max_precedents,
                tags=self._council_review_memory_tags(council_review),
            )
            self._log_observation(
                "synapse.council.memory_recall",
                request_id=self._observation_request_id(council_review, context),
                council_id=council_id,
                latency_seconds=time.perf_counter() - recall_started_at,
                verdict_status="context_ready",
            )
        except Exception as e:
            self._log_observation(
                "synapse.council.memory_recall",
                request_id=self._observation_request_id(council_review, context),
                council_id=council_id,
                latency_seconds=time.perf_counter() - recall_started_at,
                verdict_status="context_unavailable",
                failure_reason=type(e).__name__,
                level=logging.WARNING,
            )

        await publish(
            "stage1_complete",
            {
                "responses": [
                    {"member_id": r.member_id, "member_name": r.member_name, "content": r.content}
                    for r in stage1_responses
                ]
            },
        )

        return await self._complete_council(
            session_id=session_id,
            question=session.question,
            members=members,
            chairman=chairman,
            stage1_responses=stage1_responses,
            precedents=precedents,
            council_type=session.council_type,
            topic_tag=session.topic_tag,
            context=context,
            db=db,
            deliberation_rounds=[],
            human_turns=[],
            publish=publish,
            set_status=set_status,
            council_review=council_review,
        )

    # ---------------------------------------------------------------------------
    # Stage 2+3 core — shared by run() and resume()
    # ---------------------------------------------------------------------------

    async def _complete_council(
        self,
        *,
        session_id: uuid.UUID,
        question: str,
        members: list[CouncilMember],
        chairman: CouncilMember,
        stage1_responses: list[StageOneResponse],
        precedents: list,
        council_type: str,
        topic_tag: str | None,
        context: AstrocyteContext,
        db: AsyncSession,
        deliberation_rounds: list,
        human_turns: list[str],
        publish,
        set_status,
        council_review: CouncilReviewRequest | None = None,
    ) -> CouncilResult:
        """Run Stage 2 (rank) + Stage 3 (synthesise) + conflict detection + persist."""
        council_id = str(session_id)

        # --- Stage 2: Rank (skip for solo councils) ---
        await set_status(CouncilStatus.stage_2)
        await publish("stage_started", {"stage": 2})

        if council_type == "solo" or len(stage1_responses) == 1:
            from synapse.council.models import MemberRanking, RankingResult

            label = "A"
            label_map = {f"Response {label}": stage1_responses[0].member_id}
            ranking_result = RankingResult(
                label_map=label_map,
                member_rankings=[
                    MemberRanking(
                        member_id=stage1_responses[0].member_id,
                        member_name=stage1_responses[0].member_name,
                        ranking=[f"Response {label}"],
                        raw_response="",
                    )
                ],
                aggregate_scores={f"Response {label}": 1.0},
                consensus_score=1.0,
            )
        else:
            ranking_result = await run_rank(
                members=members,
                stage1_responses=stage1_responses,
                llm=self._llm,
                timeout=self._settings.stage2_timeout_seconds,
            )

        dissent_detected = self._detect_dissent(ranking_result)
        await publish(
            "stage2_complete",
            {
                "consensus_score": ranking_result.consensus_score,
                "aggregate_scores": ranking_result.aggregate_scores,
                "dissent_detected": dissent_detected,
            },
        )

        # --- Stage 3: Synthesise ---
        await set_status(CouncilStatus.stage_3)
        await publish("stage_started", {"stage": 3})

        synthesis = await run_synthesise(
            chairman=chairman,
            stage1_responses=stage1_responses,
            ranking_result=ranking_result,
            question=question,
            llm=self._llm,
            timeout=self._settings.stage3_timeout_seconds,
        )

        await publish(
            "stage3_complete",
            {"verdict": synthesis.verdict, "confidence_label": synthesis.confidence_label},
        )

        # --- Append verdict thread event ---
        thread = await get_thread_by_council(db, session_id)
        if thread:
            verdict_event = await append_event(
                db,
                thread_id=thread.id,
                event_type=ThreadEventType.verdict,
                actor_id="system",
                content=synthesis.verdict,
                metadata={
                    "council_id": council_id,
                    "confidence_label": synthesis.confidence_label,
                    "consensus_score": ranking_result.consensus_score,
                    "dissent_detected": dissent_detected,
                },
            )
            try:
                from synapse.council.thread import thread_event_dict

                await self._centrifugo.publish(
                    f"thread:{thread.id}", thread_event_dict(verdict_event)
                )
            except Exception as e:
                _logger.warning("Failed to publish verdict thread event: %s", e)

        # --- Conflict detection (B6) ---
        conflict_result = await check_conflict(
            verdict=synthesis.verdict,
            question=question,
            precedents=precedents,
            chairman_model_id=chairman.model_id,
            llm=self._llm,
            timeout=30.0,
        )

        if conflict_result.detected and thread:
            conflict_event = await append_event(
                db,
                thread_id=thread.id,
                event_type=ThreadEventType.conflict_detected,
                actor_id="system",
                content=conflict_result.summary
                or "This verdict may conflict with a past decision.",
                metadata={
                    "council_id": council_id,
                    "conflicting_content": conflict_result.conflicting_content,
                    "precedent_score": conflict_result.precedent_score,
                    "new_verdict": synthesis.verdict,
                },
            )
            try:
                from synapse.council.thread import thread_event_dict as _tdict

                await self._centrifugo.publish(f"thread:{thread.id}", _tdict(conflict_event))
            except Exception as e:
                _logger.warning("Failed to publish conflict thread event: %s", e)

        # --- Persist to DB ---
        final_status = (
            CouncilStatus.pending_approval if conflict_result.detected else CouncilStatus.closed
        )
        session = await db.get(CouncilSession, session_id)
        if session:
            session.status = final_status
            session.verdict = synthesis.verdict
            session.consensus_score = ranking_result.consensus_score
            session.confidence_label = synthesis.confidence_label
            session.dissent_detected = dissent_detected
            if final_status == CouncilStatus.closed:
                session.closed_at = datetime.now(UTC)
            if conflict_result.detected:
                session.conflict_metadata = conflict_result.model_dump()

            transcript = CouncilTranscript(
                council_id=session_id,
                round_number=len(deliberation_rounds) + 1,
                precedents=[{"content": p.content, "score": p.score} for p in precedents],
                stage1_responses=[r.model_dump() for r in stage1_responses],
                stage2_rankings=[r.model_dump() for r in ranking_result.member_rankings],
                aggregate_scores=ranking_result.aggregate_scores,
                stage3_verdict={
                    "verdict": synthesis.verdict,
                    "confidence_label": synthesis.confidence_label,
                },
                deliberation_rounds=deliberation_rounds,
            )
            db.add(transcript)
            await audit_emit(
                db,
                "council.closed"
                if final_status == CouncilStatus.closed
                else "council.pending_approval",
                session.created_by,
                tenant_id=session.tenant_id,
                resource_type="council",
                resource_id=council_id,
                metadata={
                    "verdict_preview": (synthesis.verdict or "")[:120],
                    "consensus_score": ranking_result.consensus_score,
                    "confidence_label": synthesis.confidence_label,
                },
            )
            await db.commit()

        # --- Fire webhooks (B9) ---
        if self._http_client:
            try:
                from synapse.webhooks.delivery import fire_webhooks

                if final_status == CouncilStatus.closed:
                    asyncio.create_task(
                        fire_webhooks(
                            db,
                            self._http_client,
                            "council_closed",
                            {
                                "council_id": council_id,
                                "verdict": synthesis.verdict,
                                "confidence_label": synthesis.confidence_label,
                                "consensus_score": ranking_result.consensus_score,
                            },
                            context.tenant_id,
                        )
                    )
                if conflict_result.detected:
                    asyncio.create_task(
                        fire_webhooks(
                            db,
                            self._http_client,
                            "conflict_detected",
                            {
                                "council_id": council_id,
                                "summary": conflict_result.summary,
                                "precedent_score": conflict_result.precedent_score,
                            },
                            context.tenant_id,
                        )
                    )
            except Exception as _wh_err:
                _logger.warning("Webhook firing failed: %s", _wh_err)

        # --- Notifications (EE Team+) ---
        if self._notification_dispatcher is not None and final_status == CouncilStatus.closed:
            _session_for_notif = await db.get(CouncilSession, session_id)
            if _session_for_notif is not None:
                asyncio.create_task(
                    self._notification_dispatcher.dispatch_verdict(
                        council_id=council_id,
                        question=question,
                        verdict=synthesis.verdict,
                        recipient_principal=_session_for_notif.created_by,
                        db=db,
                        tenant_id=_session_for_notif.tenant_id,
                    )
                )

        # --- Retain to Astrocyte ---
        asyncio.create_task(
            self._retain_to_astrocyte(
                session_id=council_id,
                question=question,
                stage1_responses=stage1_responses,
                synthesis=synthesis,
                consensus_score=ranking_result.consensus_score,
                council_type=council_type,
                topic_tag=topic_tag,
                context=context,
                human_turns=human_turns,
                council_review=council_review,
            )
        )

        if final_status == CouncilStatus.closed:
            await publish("session_closed", {"session_id": council_id})
        else:
            await publish(
                "pending_approval",
                {
                    "session_id": council_id,
                    "conflict_summary": conflict_result.summary,
                },
            )

        return CouncilResult(
            session_id=session_id,
            question=question,
            verdict=synthesis.verdict,
            consensus_score=ranking_result.consensus_score,
            confidence_label=synthesis.confidence_label,
            dissent_detected=dissent_detected,
            stage1_responses=stage1_responses,
            ranking_result=ranking_result,
            synthesis=synthesis,
            deliberation_rounds=[
                DeliberationRound(
                    round=rd["round"],
                    critiques=[
                        MemberCritique(**c) for c in rd.get("critiques", rd.get("attacks", []))
                    ],
                    revised_responses=[
                        StageOneResponse(**r) for r in rd.get("revised_responses", [])
                    ],
                    converged=rd.get("converged", False),
                )
                for rd in deliberation_rounds
            ],
        )

    def _detect_dissent(self, ranking_result) -> bool:
        """Flag dissent when any member's ranking significantly diverges from consensus."""
        if len(ranking_result.member_rankings) < 2:
            return False
        # Simple heuristic: consensus_score < 0.4 suggests significant dissent
        return ranking_result.consensus_score < 0.4

    async def _retain_to_astrocyte(
        self,
        session_id: str,
        question: str,
        stage1_responses,
        synthesis,
        consensus_score: float,
        council_type: str,
        topic_tag: str | None,
        context: AstrocyteContext,
        human_turns: list[str] | None = None,
        council_review: CouncilReviewRequest | None = None,
    ) -> None:
        """Retain full transcript + verdict summary to Astrocyte. Fire-and-forget.

        The transcript written to the ``councils`` bank includes human turns
        (Mode 2 messages) so future councils can recall the full deliberation
        context — not just what agents said, but what the human contributed.

        Reflection events (Mode 3 Q&A) are retained separately by the chat
        router at the point they occur, not here.
        """
        if council_review and council_review.retention == "no_retain_council":
            return
        retain_started_at = time.perf_counter()
        try:
            # Full transcript → councils bank
            # Human turns are interleaved before agent responses so the
            # semantic embedding captures the full deliberation context.
            parts = [f"Council: {question}"]
            if human_turns:
                parts.append("\n".join(f"[Human]: {msg}" for msg in human_turns))
            parts.extend(f"[{r.member_name}]: {r.content}" for r in stage1_responses)
            parts.append(f"Verdict: {synthesis.verdict}")
            full_transcript = "\n\n".join(parts)
            await self._astrocyte.retain(
                content=full_transcript,
                bank_id=Banks.COUNCILS,
                tags=council_tags(council_type, topic_tag)
                + self._council_review_memory_tags(council_review)
                + [session_id],
                context=context,
                metadata={"council_id": session_id, "consensus_score": consensus_score},
            )

            # Concise verdict → decisions bank
            verdict_summary = (
                f"Q: {question}\n\n"
                f"Verdict: {synthesis.verdict}\n"
                f"Confidence: {synthesis.confidence_label}"
            )
            await self._astrocyte.retain(
                content=verdict_summary,
                bank_id=Banks.DECISIONS,
                tags=verdict_tags(council_type, topic_tag)
                + self._council_review_memory_tags(council_review)
                + [session_id],
                context=context,
                metadata={
                    "council_id": session_id,
                    "consensus_score": consensus_score,
                    "confidence_label": synthesis.confidence_label,
                },
            )
            self._log_observation(
                "synapse.council.memory_retain",
                request_id=self._observation_request_id(council_review, context),
                council_id=session_id,
                latency_seconds=time.perf_counter() - retain_started_at,
                verdict_status="retained",
            )
        except Exception as e:
            self._log_observation(
                "synapse.council.memory_retain",
                request_id=self._observation_request_id(council_review, context),
                council_id=session_id,
                latency_seconds=time.perf_counter() - retain_started_at,
                verdict_status="retain_failed",
                failure_reason=type(e).__name__,
                level=logging.ERROR,
            )

    def _council_review_memory_query(
        self,
        question: str,
        council_review: CouncilReviewRequest | None,
    ) -> str:
        if council_review is None:
            return question
        action = council_review.proposed_action
        parts = [
            action.summary or "",
            action.goal or "",
            action.decision_kind or action.kind,
            " ".join(council_review.risk_signals.warnings[:8]),
        ]
        for summary in council_review.selected_context_summaries:
            parts.extend(str(value) for value in summary.summary.values())
        query = "\n".join(part for part in parts if part).strip()
        return query or question

    def _council_review_memory_tags(
        self,
        council_review: CouncilReviewRequest | None,
    ) -> list[str]:
        if council_review is None:
            return []
        scope = council_review.memory_scope
        tags = []
        if scope.workspace_id:
            tags.append(f"workspace:{scope.workspace_id}")
        if scope.scope_kind and scope.scope_id:
            tags.append(f"{scope.scope_kind}:{scope.scope_id}")
        return tags

    def _council_review_from_session(self, session: CouncilSession) -> CouncilReviewRequest | None:
        raw = (session.config or {}).get("council_review")
        if raw is None:
            return None
        try:
            return CouncilReviewRequest.model_validate(raw)
        except Exception as e:
            self._log_observation(
                "synapse.council.contract",
                request_id="",
                council_id=str(session.id),
                latency_seconds=0,
                verdict_status="contract_invalid",
                failure_reason=type(e).__name__,
                level=logging.WARNING,
            )
            return None

    def _observation_request_id(
        self,
        council_review: CouncilReviewRequest | None,
        context: AstrocyteContext | None,
    ) -> str:
        if council_review is not None and council_review.request_id:
            return council_review.request_id
        if context is not None and context.request_id:
            return context.request_id
        return ""

    def _log_observation(
        self,
        event: str,
        *,
        request_id: str,
        council_id: str,
        latency_seconds: float,
        verdict_status: str,
        failure_reason: str = "none",
        level: int = logging.INFO,
    ) -> None:
        _logger.log(
            level,
            "event=%s request_id_hash=%s council_id_hash=%s latency_ms=%d verdict_status=%s failure_reason=%s",
            self._safe_observation_value(event, max_chars=80) or "synapse.council",
            self._observation_hash(request_id),
            self._observation_hash(council_id),
            max(0, int(latency_seconds * 1000)),
            self._safe_observation_value(verdict_status, max_chars=80) or "unknown",
            self._safe_observation_value(failure_reason, max_chars=120) or "none",
        )

    def _observation_hash(self, value: object) -> str:
        text = self._safe_observation_value(value)
        if not text:
            return "none"
        return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]

    def _safe_observation_value(self, value: object, *, max_chars: int = 128) -> str:
        text = str(value or "").strip()
        if not text:
            return ""
        text = "".join(ch for ch in text if ord(ch) >= 0x20 and ord(ch) != 0x7F)
        return text[:max_chars]
