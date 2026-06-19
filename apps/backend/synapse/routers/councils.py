"""Councils router — CRUD, SSE stream, thread link, and Mode 3 chat."""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import time
import uuid
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from synapse.audit import emit as audit_emit
from synapse.auth.jwt import AuthenticatedUser, get_current_user
from synapse.council.models import (
    CouncilMember,
    CouncilReviewAgentPosition,
    CouncilReviewRequest,
    CouncilReviewResponse,
    CouncilReviewRiskSignals,
    CreateCouncilRequest,
)
from synapse.council.orchestrator import CouncilOrchestrator
from synapse.council.session import (
    approve_session,
    close_session,
    create_session,
    get_session,
    list_sessions,
    mark_failed,
)
from synapse.council.thread import (
    append_event,
    create_thread,
    get_thread_by_council,
    thread_event_dict,
)
from synapse.db.models import CouncilStatus, ThreadEventType
from synapse.db.session import get_session as get_db_session
from synapse.llm.client import LLMClient
from synapse.memory.banks import Banks
from synapse.memory.context import AstrocyteContext, build_context
from synapse.templates.registry import get_registry

_logger = logging.getLogger(__name__)

router = APIRouter(tags=["councils"])


# ---------------------------------------------------------------------------
# Dependency helpers
# ---------------------------------------------------------------------------


async def _dispatch_summon_safely(
    dispatcher,
    app,
    *,
    council_id: str,
    question: str,
    recipient_principal: str,
    tenant_id: str | None,
) -> None:
    """Wrap dispatch_summon with its own DB session so it can run as a fire-and-forget task."""
    try:
        async with app.state.sessionmaker() as db:
            await dispatcher.dispatch_summon(
                council_id=council_id,
                question=question,
                recipient_principal=recipient_principal,
                db=db,
                tenant_id=tenant_id,
            )
    except Exception as exc:  # pragma: no cover — never block council pipeline
        _logger.warning("Summon dispatch failed for %s: %s", recipient_principal, exc)


def _get_orchestrator(request: Request) -> CouncilOrchestrator:
    return CouncilOrchestrator(
        astrocyte=request.app.state.astrocyte,
        centrifugo=request.app.state.centrifugo,
        llm=LLMClient(request.app.state.settings),
        settings=request.app.state.settings,
        http_client=request.app.state.http_client,
        notification_dispatcher=getattr(request.app.state, "notification_dispatcher", None),
    )


def _resolve_members(
    request_members: list[CouncilMember] | None,
    settings,
) -> list[CouncilMember]:
    if request_members:
        return request_members
    return [CouncilMember(**m) for m in settings.default_members]


def _resolve_chairman(
    request_chairman: CouncilMember | None,
    settings,
) -> CouncilMember:
    if request_chairman:
        return request_chairman
    return CouncilMember(**settings.default_chairman)


def _council_review(body: CreateCouncilRequest) -> CouncilReviewRequest | None:
    raw = body.config.get("council_review") if body.config else None
    if raw is None:
        return None
    try:
        return _sanitize_council_review(CouncilReviewRequest.model_validate(raw))
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail="Invalid council_review contract") from exc


def _normalize_council_review_request(body: CreateCouncilRequest) -> CouncilReviewRequest | None:
    contract = _council_review(body)
    if contract is None:
        return None

    body.config = {
        **body.config,
        "council_review": contract.model_dump(mode="json", exclude_none=True),
    }
    body.question = _council_review_question(body.question, contract)
    return contract


def _council_review_question(fallback: str, contract: CouncilReviewRequest) -> str:
    action = contract.proposed_action
    lines = [
        "Council Review",
        "Return a concise second opinion. Do not apply changes or request tools.",
        f"Workspace: {contract.workspace_id}",
        f"Actor: {contract.actor_id}",
        f"Mode: {contract.mode}",
        f"Action: {action.kind}",
    ]
    if action.title:
        lines.append(f"Title: {action.title}")
    if action.goal:
        lines.append(f"Goal: {action.goal}")
    if action.summary:
        lines.append(f"Proposed action summary: {action.summary}")
    if action.decision_kind:
        lines.append(f"Decision kind: {action.decision_kind}")
    if contract.risk_signals.risk_level:
        lines.append(f"Risk signal: {contract.risk_signals.risk_level}")
    for item in contract.selected_context_summaries:
        if item.detail_level:
            lines.append(f"Context detail: {item.detail_level}")
        if item.summary:
            lines.append(
                "Selected context summary: "
                + json.dumps(item.summary, ensure_ascii=True, sort_keys=True)[:2000]
            )
        if item.warnings:
            lines.append("Context warnings: " + "; ".join(item.warnings[:8]))
    if not action.summary and fallback:
        lines.append(f"Review prompt: {fallback[:2000]}")
    lines.append("Return a summary, recommendation, confidence, reasons, risks, and dissent.")
    return "\n".join(lines)


def _council_request_id(request: Request, contract: CouncilReviewRequest | None) -> str:
    header_request_id = _safe_identifier(request.headers.get("x-request-id"))
    if header_request_id:
        return header_request_id
    if contract is not None:
        return _safe_identifier(contract.request_id)
    return ""


def _council_created_metadata(
    body: CreateCouncilRequest,
    contract: CouncilReviewRequest | None,
    members: list[CouncilMember],
    request_id: str,
) -> dict:
    metadata = {
        "council_type": body.council_type or "llm",
        "member_count": len(members),
    }
    if contract is None:
        metadata["question_preview"] = body.question[:120]
        return metadata

    metadata.update(
        {
            "council_review_contract_version": contract.contract_version,
            "request_id_hash": _observation_hash(request_id),
            "workspace_id_hash": _observation_hash(contract.workspace_id),
            "mode": contract.mode,
            "verdict_status": CouncilStatus.pending,
        }
    )
    return metadata


def _council_thread_title(
    body: CreateCouncilRequest,
    contract: CouncilReviewRequest | None,
) -> str:
    if contract is None:
        return body.question[:120]
    action = contract.proposed_action
    title = action.title or action.decision_kind or action.kind or "Council Review"
    return _safe_identifier(title, max_chars=120) or "Council Review"


def _council_started_metadata(
    session_id: uuid.UUID,
    body: CreateCouncilRequest,
    contract: CouncilReviewRequest | None,
    members: list[CouncilMember],
    request_id: str,
) -> dict:
    metadata = {
        "council_id": str(session_id),
        "member_count": len(members),
    }
    if contract is None:
        metadata["question"] = body.question
        return metadata

    metadata.update(
        {
            "council_review_contract_version": contract.contract_version,
            "request_id_hash": _observation_hash(request_id),
            "workspace_id_hash": _observation_hash(contract.workspace_id),
            "mode": contract.mode,
            "verdict_status": CouncilStatus.pending,
        }
    )
    return metadata


def _log_council_observation(
    event: str,
    *,
    request_id: str,
    council_id: str,
    latency_seconds: float,
    verdict_status: str,
    failure_reason: str = "none",
    level: int = logging.INFO,
    exc_info: bool = False,
) -> None:
    _logger.log(
        level,
        "event=%s request_id_hash=%s council_id_hash=%s latency_ms=%d verdict_status=%s failure_reason=%s",
        _safe_identifier(event, max_chars=80) or "synapse.council",
        _observation_hash(request_id),
        _observation_hash(council_id),
        max(0, int(latency_seconds * 1000)),
        _safe_identifier(verdict_status, max_chars=80) or "unknown",
        _safe_identifier(failure_reason, max_chars=120) or "none",
        exc_info=exc_info,
    )


def _safe_identifier(value: object, *, max_chars: int = 128) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    text = "".join(ch for ch in text if ord(ch) >= 0x20 and ord(ch) != 0x7F)
    return text[:max_chars]


def _observation_hash(value: object) -> str:
    text = _safe_identifier(value)
    if not text:
        return "none"
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------------------
# POST /v1/councils
# ---------------------------------------------------------------------------


@router.post(
    "/councils",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=dict,
    summary="Start a new council session",
)
async def create_council(
    body: CreateCouncilRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> dict:
    request_started_at = time.perf_counter()
    settings = request.app.state.settings

    # Canonical opt-in for red team / deliberation modes is `settings.mode`
    # (Cerebro's field; Synapse accepts it as an alias for `config` via
    # `CreateCouncilRequest`). Promote the mode into the existing
    # `council_type` field for red team — Synapse's orchestrator branches
    # on that to take the adversarial path. `mode="deliberation"` is a
    # no-op here: Synapse runs the critique/revise loop by default for any
    # ≥2-member non-solo council when `deliberation_enabled` is set
    # globally (see config.py + orchestrator.py:155). `mode="standard"`
    # is the default and needs no override.
    if (mode := body.config.get("mode")) == "red_team" and body.council_type == "llm":
        body.council_type = "red_team"
    _ = mode  # explicit binding for the walrus assignment

    # Template resolution — apply before member/chairman fallbacks so that
    # explicit request fields always win over template defaults.
    body = _apply_template(body)
    council_review = _normalize_council_review_request(body)
    request_id = _council_request_id(request, council_review)

    members = _resolve_members(body.members, settings)
    chairman = _resolve_chairman(body.chairman, settings)

    council_session = await create_session(
        db=db,
        request=body,
        members=members,
        chairman=chairman,
        created_by=user.principal,
        tenant_id=user.tenant_id,
    )
    session_id = council_session.id
    await audit_emit(
        db,
        "council.created",
        user.principal,
        tenant_id=user.tenant_id,
        resource_type="council",
        resource_id=str(session_id),
        metadata=_council_created_metadata(body, council_review, members, request_id),
    )

    # Create the thread that backs this council's chat surface
    thread = await create_thread(
        db,
        council_id=session_id,
        created_by=user.principal,
        tenant_id=user.tenant_id,
        title=_council_thread_title(body, council_review),
    )

    # Append the council_started event so the thread has a clear origin marker
    started_event = await append_event(
        db,
        thread_id=thread.id,
        event_type=ThreadEventType.council_started,
        actor_id="system",
        metadata=_council_started_metadata(session_id, body, council_review, members, request_id),
    )
    await _publish(request, thread.id, thread_event_dict(started_event))

    context = build_context(user)
    if request_id:
        context = AstrocyteContext(
            principal=context.principal,
            tenant_id=context.tenant_id,
            request_id=request_id,
        )

    # B7 — Scheduled council: register with the runner and return immediately.
    # The runner will fire the orchestrator at run_at.
    if body.run_at:
        request.app.state.scheduler.schedule(request.app, session_id, body.run_at)
        _log_council_observation(
            "synapse.council.create",
            request_id=request_id,
            council_id=str(session_id),
            latency_seconds=time.perf_counter() - request_started_at,
            verdict_status=CouncilStatus.scheduled,
        )
        return {
            "session_id": str(session_id),
            "thread_id": str(thread.id),
            "status": CouncilStatus.scheduled,
            "run_at": body.run_at.isoformat(),
        }

    # B3 — Schedule contribution_deadline resume if set
    if body.contribution_deadline_hours and body.council_type == "async":
        deadline = council_session.contribution_deadline
        if deadline:
            request.app.state.scheduler.schedule_resume(request.app, session_id, deadline)

    orchestrator = _get_orchestrator(request)

    # Fire summon notifications for human members of async councils.
    # Convention (per ContributeRequest docstring): a human member's
    # `model_id` is the principal string, e.g. "user:alice".
    dispatcher = getattr(request.app.state, "notification_dispatcher", None)
    if dispatcher is not None and body.council_type == "async":
        human_members = [m for m in members if m.member_type == "human" and m.model_id]
        for hm in human_members:
            asyncio.create_task(
                _dispatch_summon_safely(
                    dispatcher,
                    request.app,
                    council_id=str(session_id),
                    question=body.question,
                    recipient_principal=hm.model_id,
                    tenant_id=user.tenant_id,
                )
            )

    async def _run() -> None:
        run_started_at = time.perf_counter()
        async with request.app.state.sessionmaker() as bg_db:
            try:
                result = await orchestrator.run(
                    session_id=session_id,
                    question=body.question,
                    members=members,
                    chairman=chairman,
                    context=context,
                    db=bg_db,
                    council_type=body.council_type,
                    topic_tag=body.topic_tag,
                    council_review=council_review,
                )
                _log_council_observation(
                    "synapse.council.run",
                    request_id=request_id,
                    council_id=str(session_id),
                    latency_seconds=time.perf_counter() - run_started_at,
                    verdict_status="waiting_contributions" if result is None else "completed",
                )
            except Exception as exc:
                failure_reason = type(exc).__name__
                _log_council_observation(
                    "synapse.council.run",
                    request_id=request_id,
                    council_id=str(session_id),
                    latency_seconds=time.perf_counter() - run_started_at,
                    verdict_status="failed",
                    failure_reason=failure_reason,
                    level=logging.ERROR,
                    exc_info=True,
                )
                async with request.app.state.sessionmaker() as err_db:
                    await mark_failed(err_db, session_id, error=failure_reason)

    # Fire and forget — client polls or listens via Centrifugo/SSE
    asyncio.create_task(_run())

    _log_council_observation(
        "synapse.council.create",
        request_id=request_id,
        council_id=str(session_id),
        latency_seconds=time.perf_counter() - request_started_at,
        verdict_status=CouncilStatus.pending,
    )
    return {
        "session_id": str(session_id),
        "thread_id": str(thread.id),
        "status": CouncilStatus.pending,
    }


# ---------------------------------------------------------------------------
# GET /v1/councils
# ---------------------------------------------------------------------------


@router.get(
    "/councils",
    summary="List council sessions for the current user",
)
async def list_councils(
    request: Request,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> list[dict]:
    sessions = await list_sessions(
        db,
        tenant_id=user.tenant_id,
        created_by=user.principal,
        limit=limit,
        offset=offset,
    )
    return [_session_summary(s) for s in sessions]


# ---------------------------------------------------------------------------
# GET /v1/councils/{session_id}
# ---------------------------------------------------------------------------


@router.get(
    "/councils/{session_id}",
    summary="Get a council session by ID",
)
async def get_council(
    session_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> dict:
    session = await _load_council(db, session_id, user)
    if not session:
        raise HTTPException(status_code=404, detail="Council session not found")
    _assert_owns(session, user)
    return _session_detail(session)


# ---------------------------------------------------------------------------
# GET /v1/councils/{session_id}/thread
# ---------------------------------------------------------------------------


@router.get(
    "/councils/{session_id}/thread",
    summary="Get the thread ID for a council session",
)
async def get_council_thread(
    session_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> dict:
    session = await _load_council(db, session_id, user)
    if not session:
        raise HTTPException(status_code=404, detail="Council session not found")
    _assert_owns(session, user)

    thread = await get_thread_by_council(db, session_id)
    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found for this council")

    return {"session_id": str(session_id), "thread_id": str(thread.id)}


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# POST /v1/councils/{session_id}/close
# ---------------------------------------------------------------------------


@router.post(
    "/councils/{session_id}/close",
    summary="Force-close a council session",
)
async def close_council(
    session_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> dict:
    """Close a council immediately, regardless of current status.

    Useful for the ``@close`` human-in-the-loop directive — terminates an
    in-progress council and accepts whatever deliberation has occurred so far.
    If the council is in ``pending_approval`` this overrides the conflict block.
    """
    session = await _load_council(db, session_id, user)
    if not session:
        raise HTTPException(status_code=404, detail="Council session not found")
    _assert_owns(session, user)

    updated = await close_session(db, session_id)
    return {
        "session_id": str(session_id),
        "status": updated.status if updated else "closed",
        "verdict": updated.verdict if updated else None,
    }


# ---------------------------------------------------------------------------
# POST /v1/councils/{session_id}/approve
# ---------------------------------------------------------------------------


@router.post(
    "/councils/{session_id}/approve",
    summary="Approve a council verdict that is pending human review",
)
async def approve_council(
    session_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> dict:
    """Approve a council in ``pending_approval`` state and close it.

    Returns 409 if the session is not in ``pending_approval``.
    """
    session = await _load_council(db, session_id, user)
    if not session:
        raise HTTPException(status_code=404, detail="Council session not found")
    _assert_owns(session, user)

    from synapse.db.models import CouncilStatus

    if session.status != CouncilStatus.pending_approval:
        raise HTTPException(
            status_code=409,
            detail=f"Council is not pending approval (status: {session.status})",
        )

    updated = await approve_session(db, session_id)
    await audit_emit(
        db,
        "council.approved",
        user.principal,
        tenant_id=user.tenant_id,
        resource_type="council",
        resource_id=str(session_id),
        metadata={"verdict_preview": (updated.verdict or "")[:120] if updated else ""},
    )
    await db.commit()
    return {
        "session_id": str(session_id),
        "status": updated.status if updated else "closed",
        "verdict": updated.verdict if updated else None,
    }


# ---------------------------------------------------------------------------
# POST /v1/councils/{session_id}/chat  — Mode 3: chat with closed verdict
# ---------------------------------------------------------------------------


class ChatRequest(BaseModel):
    message: str


@router.post(
    "/councils/{session_id}/chat",
    summary="Chat with a closed council verdict (Mode 3 — powered by Astrocyte reflect)",
)
async def chat_with_verdict(
    session_id: uuid.UUID,
    body: ChatRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> dict:
    session = await _load_council(db, session_id, user)
    if not session:
        raise HTTPException(status_code=404, detail="Council session not found")
    _assert_owns(session, user)
    if session.status != CouncilStatus.closed:
        raise HTTPException(
            status_code=409,
            detail=f"Council is not closed (status: {session.status}). Mode 3 chat requires a closed council.",
        )

    context = build_context(user)
    astrocyte = request.app.state.astrocyte

    # Reflect on the councils bank scoped to this session
    reflect_result = await astrocyte.reflect(
        query=body.message,
        bank_id=Banks.COUNCILS,
        context=context,
    )

    # Append the user message and reflection to the thread
    thread = await get_thread_by_council(db, session_id)
    if thread:
        user_event = await append_event(
            db,
            thread_id=thread.id,
            event_type=ThreadEventType.user_message,
            actor_id=user.principal,
            actor_name=user.raw_claims.get("name") or user.sub,
            content=body.message,
        )
        await _publish(request, thread.id, thread_event_dict(user_event))

        reflection_event = await append_event(
            db,
            thread_id=thread.id,
            event_type=ThreadEventType.reflection,
            actor_id="system",
            content=reflect_result.answer,
            metadata={"sources": reflect_result.sources},
        )
        await _publish(request, thread.id, thread_event_dict(reflection_event))

    # Retain the Q&A exchange to the councils bank so future councils can recall it
    asyncio.create_task(
        _retain_reflection(
            astrocyte=astrocyte,
            council_id=str(session_id),
            question=body.message,
            answer=reflect_result.answer,
            sources=reflect_result.sources,
            context=context,
        )
    )

    return {
        "answer": reflect_result.answer,
        "sources": reflect_result.sources,
        "session_id": str(session_id),
    }


# ---------------------------------------------------------------------------
# GET /v1/councils/{session_id}/stream  — SSE fallback
# ---------------------------------------------------------------------------


@router.get(
    "/councils/{session_id}/stream",
    summary="SSE stream for council events (fallback — prefer Centrifugo WS)",
)
async def stream_council(
    session_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
    user: AuthenticatedUser = Depends(get_current_user),
) -> StreamingResponse:
    session = await _load_council(db, session_id, user)
    if not session:
        raise HTTPException(status_code=404, detail="Council session not found")
    _assert_owns(session, user)

    async def _event_generator() -> AsyncIterator[str]:
        """Poll DB status every 1 s and emit SSE events until closed/failed."""
        last_status: str | None = None
        async with request.app.state.sessionmaker() as poll_db:
            while True:
                if await request.is_disconnected():
                    break
                s = await get_session(poll_db, session_id)
                if s is None:
                    break
                if s.status != last_status:
                    last_status = s.status
                    data = json.dumps({"status": s.status, "session_id": str(session_id)})
                    yield f"data: {data}\n\n"
                if s.status in (CouncilStatus.closed, CouncilStatus.failed):
                    if s.status == CouncilStatus.closed:
                        payload = json.dumps(
                            {
                                "event": "session_closed",
                                "verdict": s.verdict,
                                "consensus_score": s.consensus_score,
                                "confidence_label": s.confidence_label,
                            }
                        )
                        yield f"data: {payload}\n\n"
                    break
                await asyncio.sleep(1)

    return StreamingResponse(
        _event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------


def _apply_template(body: CreateCouncilRequest) -> CreateCouncilRequest:
    """Merge template defaults into the request.  Explicit request fields win."""
    if not body.template_id:
        return body
    tmpl = get_registry().get(body.template_id)
    if tmpl is None:
        raise HTTPException(
            status_code=422,
            detail=f"Template '{body.template_id}' not found",
        )
    return CreateCouncilRequest(
        question=body.question,
        template_id=body.template_id,
        # Explicit overrides win; fall back to template values
        members=body.members or [CouncilMember(**m) for m in tmpl.members],
        chairman=body.chairman or CouncilMember(**tmpl.chairman),
        council_type=body.council_type if body.council_type != "llm" else tmpl.council_type,
        topic_tag=body.topic_tag or tmpl.topic_tag,
        # Merge configs: template base, then request overrides on top
        config={**tmpl.config, **body.config},
    )


async def _publish(request: Request, thread_id: uuid.UUID, payload: dict) -> None:
    """Best-effort Centrifugo publish — never raises (DB write already succeeded)."""
    try:
        await request.app.state.centrifugo.publish(f"thread:{thread_id}", payload)
    except Exception:
        _logger.warning("Centrifugo publish failed for thread %s", thread_id, exc_info=True)


async def _retain_reflection(
    astrocyte,
    council_id: str,
    question: str,
    answer: str,
    sources: list,
    context,
) -> None:
    """Retain a Mode 3 Q&A exchange to the councils bank. Fire-and-forget."""
    try:
        content = f"Mode 3 Q&A — Council {council_id}\n\nQ: {question}\n\nA: {answer}"
        await astrocyte.retain(
            content=content,
            bank_id=Banks.COUNCILS,
            tags=["reflection", council_id],
            context=context,
            metadata={"council_id": council_id, "type": "reflection"},
        )
    except Exception as exc:
        _logger.error("Failed to retain reflection for council %s: %s", council_id, exc)


def _assert_owns(session, user: AuthenticatedUser) -> None:
    """Belt-and-braces tenant check kept around even though the fetch
    helpers below now pre-filter by tenant. The combined effect is
    defense-in-depth: a future code path that bypasses ``_load_council``
    still cannot return cross-tenant rows."""
    if "admin" in (user.roles or []):
        return
    if user.tenant_id and session.tenant_id != user.tenant_id:
        raise HTTPException(status_code=403, detail="Access denied")


async def _load_council(
    db: AsyncSession,
    session_id,
    user: AuthenticatedUser,
):
    """Tenant-scoped council fetch.

    For non-admins the query filters by ``tenant_id`` directly, so a
    cross-tenant ``session_id`` returns ``None`` and the caller raises
    404 — eliminating the 403/404 distinction that previously let a
    caller probe whether a session existed in another tenant. Admins
    bypass the filter so they can investigate any tenant.
    """
    if "admin" in (user.roles or []):
        return await get_session(db, session_id)
    return await get_session(db, session_id, tenant_id=user.tenant_id)


def _session_summary(s) -> dict:
    return {
        "session_id": str(s.id),
        "question": s.question[:120] + "..." if len(s.question) > 120 else s.question,
        "status": s.status,
        "council_type": s.council_type,
        "confidence_label": s.confidence_label,
        "consensus_score": s.consensus_score,
        "created_at": s.created_at.isoformat(),
        "closed_at": s.closed_at.isoformat() if s.closed_at else None,
        "failure_reason": s.config.get("_error") if s.config else None,
        "conflict_detected": bool(s.conflict_metadata.get("detected"))
        if s.conflict_metadata
        else False,
    }


def _session_detail(s) -> dict:
    detail = {
        "session_id": str(s.id),
        "question": s.question,
        "status": s.status,
        "council_type": s.council_type,
        "verdict": s.verdict,
        "confidence_label": s.confidence_label,
        "consensus_score": s.consensus_score,
        "dissent_detected": s.dissent_detected,
        "topic_tag": s.topic_tag,
        "template_id": s.template_id,
        "created_at": s.created_at.isoformat(),
        "closed_at": s.closed_at.isoformat() if s.closed_at else None,
        "failure_reason": s.config.get("_error") if s.config else None,
        "members": s.members,
        "chairman": s.chairman,
        "conflict_metadata": s.conflict_metadata,
        # B3 — async councils
        "quorum": s.quorum,
        "contributions_received": len(s.contributions) if s.contributions else 0,
        "contribution_deadline": (
            s.contribution_deadline.isoformat() if s.contribution_deadline else None
        ),
        # B7 — scheduling
        "run_at": s.run_at.isoformat() if s.run_at else None,
    }
    if review_response := _council_review_response(s):
        detail["council_review_response"] = review_response
    return detail


def _council_review_response(s) -> dict | None:
    contract = _council_review_from_config(s.config or {})
    if contract is None:
        return None

    status_value, stage = _council_review_status_stage(s.status)
    summary = _safe_council_text(s.verdict or "", fallback="")
    confidence = _safe_council_text(s.confidence_label or "", fallback="")
    if confidence not in {"low", "medium", "high"}:
        confidence = contract.risk_signals.confidence_label or "medium"
    risk_signals = _council_review_response_risk_signals(s, contract)
    risks = _council_review_response_risks(s, risk_signals)
    dissent = ["The review found differing considerations."] if s.dissent_detected else []
    recommendation = _council_review_recommendation(summary)
    agent_positions = _council_review_agent_positions(
        s,
        recommendation=recommendation,
        confidence_label=confidence,
    )
    updated_at = s.closed_at or s.created_at
    response = CouncilReviewResponse(
        contract_version=contract.contract_version,
        workspace_id=contract.workspace_id,
        actor_id=contract.actor_id,
        request_id=contract.request_id,
        mode=contract.mode,
        status=status_value,
        stage=stage,
        selected_context_summaries=contract.selected_context_summaries,
        proposed_action=contract.proposed_action,
        recommendation=recommendation,
        summary=summary,
        confidence_label=confidence,
        rationale=[summary] if summary else [],
        risks=risks,
        dissent=dissent,
        agent_positions=agent_positions,
        risk_signals=risk_signals,
        memory_scope=contract.memory_scope,
        updated_at=updated_at.isoformat() if updated_at else None,
    )
    return response.model_dump(mode="json", exclude_none=True)


def _council_review_from_config(config: dict) -> CouncilReviewRequest | None:
    raw = config.get("council_review") if config else None
    if raw is None:
        return None
    try:
        return _sanitize_council_review(CouncilReviewRequest.model_validate(raw))
    except ValidationError:
        _logger.warning("Stored council_review contract is invalid", exc_info=True)
        return None


def _sanitize_council_review(contract: CouncilReviewRequest) -> CouncilReviewRequest:
    data = contract.model_dump(mode="json", exclude_none=True)
    for key in (
        "workspace_id",
        "actor_id",
        "request_id",
        "source",
        "mode",
        "template",
        "retention",
    ):
        if key in data:
            data[key] = _safe_council_text(data[key], fallback="")
    data["selected_context_summaries"] = [
        {
            **item,
            "detail_level": _safe_council_text(item.get("detail_level"), fallback=""),
            "availability": _safe_council_text(item.get("availability"), fallback=""),
            "summary": _sanitize_council_summary(item.get("summary", {}), depth=3),
            "warnings": _safe_council_list(item.get("warnings", [])),
        }
        for item in data.get("selected_context_summaries", [])
    ][:16]
    proposed = data.get("proposed_action", {})
    for key in ("kind", "title", "summary", "goal", "decision_kind"):
        if key in proposed:
            proposed[key] = _safe_council_text(proposed[key], fallback="")
    proposed["proposal_ids"] = _safe_council_list(proposed.get("proposal_ids", []))
    proposed["scenario_ids"] = _safe_council_list(proposed.get("scenario_ids", []))
    if context_ref := proposed.get("context_ref"):
        context_ref["kind"] = _safe_council_text(context_ref.get("kind"), fallback="")
        context_ref["id"] = _safe_council_text(context_ref.get("id"), fallback="")
        context_ref["label"] = _safe_council_text(context_ref.get("label"), fallback="")
        context_ref["metadata"] = {
            _safe_council_text(key, fallback=""): _safe_council_text(value, fallback="")
            for key, value in context_ref.get("metadata", {}).items()
            if _safe_council_text(key, fallback="") and _safe_council_text(value, fallback="")
        }
    data["proposed_action"] = proposed
    risk = data.get("risk_signals", {})
    risk["risk_level"] = _safe_council_text(risk.get("risk_level"), fallback="")
    risk["confidence_label"] = _safe_council_text(risk.get("confidence_label"), fallback="")
    risk["warnings"] = _safe_council_list(risk.get("warnings", []))
    data["risk_signals"] = risk
    scope = data.get("memory_scope", {})
    for key in ("workspace_id", "scope_kind", "scope_id", "retention"):
        if key in scope:
            scope[key] = _safe_council_text(scope[key], fallback="")
    data["memory_scope"] = scope
    return CouncilReviewRequest.model_validate(data)


def _sanitize_council_summary(value: object, *, depth: int) -> object:
    if depth <= 0:
        return None
    if isinstance(value, dict):
        output = {}
        for key, item in list(value.items())[:16]:
            clean_key = _safe_council_text(key, fallback="")
            if not clean_key:
                continue
            clean_value = _sanitize_council_summary(item, depth=depth - 1)
            if clean_value not in (None, "", [], {}):
                output[clean_key] = clean_value
        return output
    if isinstance(value, list):
        return [
            clean
            for clean in (_sanitize_council_summary(item, depth=depth - 1) for item in value[:16])
            if clean not in (None, "", [], {})
        ]
    if isinstance(value, str):
        return _safe_council_text(value, fallback="")
    if isinstance(value, (bool, int, float)):
        return value
    if value is None:
        return None
    return _safe_council_text(value, fallback="")


def _council_review_status_stage(status_value: str) -> tuple[str, str]:
    status_lower = (status_value or "").strip().lower()
    if status_lower in {"", "pending", "scheduled", "queued"}:
        return "queued", "preparing"
    if status_lower in {"stage_1", "waiting_contributions", "collecting", "running"}:
        return "running", "consulting"
    if status_lower in {"stage_2", "stage_3", "pending_approval", "deliberating"}:
        return "running", "building_verdict"
    if status_lower in {"closed", "completed", "done"}:
        return "completed", "review_ready"
    if status_lower == "blocked":
        return "blocked", "failed"
    if status_lower in {"cancelled", "canceled"}:
        return "cancelled", "failed"
    if status_lower in {"failed", "error"}:
        return "failed", "failed"
    return "running", "preparing"


def _council_review_recommendation(summary: str) -> str:
    lower = summary.lower()
    if "do not proceed" in lower or "avoid" in lower:
        return "do_not_proceed"
    if "defer" in lower or "wait" in lower:
        return "defer"
    if "revise" in lower or "adjust" in lower:
        return "revise"
    if "proceed" in lower:
        return "proceed"
    return "review"


def _council_review_response_risk_signals(
    s,
    contract: CouncilReviewRequest,
) -> CouncilReviewRiskSignals:
    warnings = _safe_council_list(contract.risk_signals.warnings)
    risk_level = contract.risk_signals.risk_level or ""
    requires_human_review = contract.risk_signals.requires_human_review
    conflict_metadata = s.conflict_metadata if isinstance(s.conflict_metadata, dict) else {}
    if conflict_metadata.get("detected"):
        risk_level = "high"
        requires_human_review = True
        if summary := _safe_council_text(conflict_metadata.get("summary") or "", fallback=""):
            warnings.append(summary)
    elif s.dissent_detected and not risk_level:
        risk_level = "medium"
        warnings.append("Dissent was detected in the council review.")
    return CouncilReviewRiskSignals(
        risk_level=risk_level or None,
        confidence_label=s.confidence_label or contract.risk_signals.confidence_label,
        warnings=_safe_council_list(warnings),
        requires_human_review=requires_human_review,
    )


def _council_review_response_risks(s, risk_signals: CouncilReviewRiskSignals) -> list[str]:
    risks = list(risk_signals.warnings)
    conflict_metadata = s.conflict_metadata if isinstance(s.conflict_metadata, dict) else {}
    if conflict_metadata.get("detected"):
        conflict = _safe_council_text(conflict_metadata.get("summary") or "", fallback="")
        if conflict and conflict not in risks:
            risks.append(conflict)
    return _safe_council_list(risks)


def _council_review_agent_positions(
    s,
    *,
    recommendation: str,
    confidence_label: str,
) -> list[CouncilReviewAgentPosition]:
    transcript = getattr(s, "transcript", None)
    stage1_responses = getattr(transcript, "stage1_responses", None)
    if not isinstance(stage1_responses, list):
        return []

    aggregate_scores = getattr(transcript, "aggregate_scores", None)
    score_map = aggregate_scores if isinstance(aggregate_scores, dict) else {}
    rank_by_label = _council_review_rank_by_label(score_map)
    aggregate_position = _council_review_position_from_recommendation(recommendation)
    positions: list[CouncilReviewAgentPosition] = []

    for index, raw_response in enumerate(stage1_responses[:8]):
        if not isinstance(raw_response, dict):
            continue
        member_name = _safe_council_text(raw_response.get("member_name"), fallback="")
        content = _safe_council_text(raw_response.get("content"), fallback="")
        error = _safe_council_text(raw_response.get("error"), fallback="")
        if not (member_name or content or error):
            continue

        response_label = f"Response {chr(65 + index)}"
        position = _council_review_position_from_summary(content)
        dissent = (
            position != "review"
            and aggregate_position != "review"
            and position != aggregate_position
        )
        summary = _safe_council_agent_summary(content or error)
        if not summary:
            summary = "This council agent did not return a usable safe summary."
        positions.append(
            CouncilReviewAgentPosition(
                agent_id=f"agent_{index + 1}",
                agent_label=member_name or f"Agent {index + 1}",
                position=position,
                confidence_label=_council_review_agent_confidence(
                    raw_response,
                    fallback=confidence_label,
                ),
                summary=summary,
                dissent=dissent,
                rank=rank_by_label.get(response_label),
            )
        )
    return positions


def _council_review_agent_confidence(raw_response: dict, *, fallback: str) -> str | None:
    confidence = _safe_council_text(raw_response.get("confidence_label"), fallback="")
    if confidence in {"low", "medium", "high"}:
        return confidence
    return fallback or None


def _council_review_rank_by_label(aggregate_scores: dict) -> dict[str, int]:
    clean_scores: list[tuple[str, float]] = []
    for label, score in aggregate_scores.items():
        clean_label = _safe_council_text(label, fallback="")
        if not clean_label:
            continue
        try:
            clean_scores.append((clean_label, float(score)))
        except (TypeError, ValueError):
            continue
    clean_scores.sort(key=lambda item: item[1])
    return {label: index for index, (label, _) in enumerate(clean_scores, start=1)}


def _council_review_position_from_summary(summary: str) -> str:
    lower = summary.lower()
    if "do not proceed" in lower or "reject" in lower or "avoid" in lower or "block" in lower:
        return "reject"
    if "needs human review" in lower or "human review" in lower or "defer" in lower:
        return "needs_human_review"
    if "revise" in lower or "adjust" in lower or "wait" in lower:
        return "needs_human_review"
    if "approve" in lower or "proceed" in lower:
        return "approve"
    return "review"


def _council_review_position_from_recommendation(recommendation: str) -> str:
    if recommendation == "proceed":
        return "approve"
    if recommendation == "do_not_proceed":
        return "reject"
    if recommendation in {"defer", "revise"}:
        return "needs_human_review"
    return "review"


def _safe_council_agent_summary(value: object) -> str:
    text = _safe_council_text(value, fallback="")
    if len(text) <= 360:
        return text
    return f"{text[:357].rstrip()}..."


def _safe_council_list(values: list[str]) -> list[str]:
    output: list[str] = []
    for value in values:
        clean = _safe_council_text(value, fallback="")
        if clean and clean not in output:
            output.append(clean)
    return output[:16]


def _safe_council_text(value: object, *, fallback: str) -> str:
    text = str(value or "").strip()
    if not text:
        return fallback
    text = "".join(ch for ch in text if ord(ch) >= 0x20 and ord(ch) != 0x7F)
    lower = text.lower()
    forbidden = [
        "raw_prompt",
        "raw prompt",
        "raw_response",
        "raw response",
        "request_id",
        "request id",
        "request:",
        "session_id",
        "session id",
        "thread_id",
        "thread id",
        "provider_request",
        "provider request",
        "runtime_request",
        "runtime request",
        "model_id",
        "model id",
        "member_id",
        "member id",
        "openai/",
        "anthropic/",
        "google/",
        "x-ai/",
        "idempotency",
        "credential_id",
        "credential id",
        "provider_key",
        "provider key",
        "provider_secret",
        "provider secret",
        "backend_config",
        "backend config",
        "raw_memory",
        "raw memory",
        "sk-",
        "bearer ",
        "authorization:",
    ]
    if any(fragment in lower for fragment in forbidden):
        return fallback
    return text[:2000]
