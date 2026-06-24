"""Tests for CouncilOrchestrator — integration-level, all I/O mocked."""

from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from synapse.council.models import (
    ConflictResult,
    CouncilMember,
    CouncilResult,
    CouncilReviewRequest,
)
from synapse.council.orchestrator import CouncilOrchestrator
from synapse.memory.context import AstrocyteContext
from tests.council_review_fixtures import council_review_contract_fixture

# Patch targets for B5/B6 additions
_NO_THREAD = patch(
    "synapse.council.orchestrator.get_thread_by_council", new=AsyncMock(return_value=None)
)
_NO_CONFLICT = patch(
    "synapse.council.orchestrator.check_conflict",
    new=AsyncMock(return_value=ConflictResult(detected=False)),
)


@pytest.fixture
def orchestrator(mock_astrocyte, mock_centrifugo, mock_llm):
    settings = MagicMock()
    settings.stage1_timeout_seconds = 10
    settings.stage2_timeout_seconds = 10
    settings.stage3_timeout_seconds = 10
    settings.max_precedents = 3
    # B5 deliberation — disabled in unit tests (tested separately)
    settings.deliberation_enabled = False
    settings.max_deliberation_rounds = 1
    settings.convergence_threshold = 0.72
    settings.critique_timeout_seconds = 10
    settings.revise_timeout_seconds = 10
    return CouncilOrchestrator(
        astrocyte=mock_astrocyte,
        centrifugo=mock_centrifugo,
        llm=mock_llm,
        settings=settings,
    )


@pytest.fixture
def context():
    return AstrocyteContext(principal="user-1", tenant_id="tenant-test")


@pytest.fixture
def mock_db():
    """Minimal async DB mock that satisfies orchestrator's set_status + persist logic."""
    db = AsyncMock()
    session_obj = MagicMock()
    session_obj.status = "pending"
    session_obj.config = {}
    db.get = AsyncMock(return_value=session_obj)
    db.commit = AsyncMock()
    db.add = MagicMock()
    return db


@pytest.fixture
def two_members():
    return [
        CouncilMember(model_id="openai/gpt-4o", name="GPT"),
        CouncilMember(model_id="anthropic/claude-3-5-sonnet-20241022", name="Claude"),
    ]


@pytest.fixture
def chairman():
    return CouncilMember(model_id="anthropic/claude-opus-4-5", name="Chair")


# ---------------------------------------------------------------------------
# Happy path — full council
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_orchestrator_run_full_council(orchestrator, mock_db, two_members, chairman, context):
    """Full 3-stage run should return a CouncilResult with verdict."""
    with patch("synapse.council.orchestrator.asyncio.create_task"), _NO_THREAD, _NO_CONFLICT:
        result = await orchestrator.run(
            session_id=uuid.uuid4(),
            question="What should we build next?",
            members=two_members,
            chairman=chairman,
            context=context,
            db=mock_db,
            council_type="llm",
            topic_tag="product",
        )

    assert isinstance(result, CouncilResult)
    assert result.verdict is not None
    assert 0.0 <= result.consensus_score <= 1.0
    assert result.confidence_label in ("high", "medium", "low")


@pytest.mark.asyncio
async def test_orchestrator_publishes_stage_events(
    orchestrator, mock_db, two_members, chairman, context
):
    """Centrifugo publish_council_event should be called for key lifecycle events."""
    with patch("synapse.council.orchestrator.asyncio.create_task"), _NO_THREAD, _NO_CONFLICT:
        await orchestrator.run(
            session_id=uuid.uuid4(),
            question="Q?",
            members=two_members,
            chairman=chairman,
            context=context,
            db=mock_db,
        )

    calls = orchestrator._centrifugo.publish_council_event.call_args_list
    event_types = [c.args[1] for c in calls]
    assert "stage_started" in event_types
    assert "stage1_complete" in event_types
    assert "stage2_complete" in event_types
    assert "stage3_complete" in event_types
    assert "session_closed" in event_types


# ---------------------------------------------------------------------------
# Solo council — Stage 2 bypassed
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_orchestrator_solo_council_bypasses_rank(orchestrator, mock_db, context):
    """Solo council skips Stage 2 — consensus_score should be 1.0."""
    solo_member = [CouncilMember(model_id="openai/gpt-4o", name="GPT")]
    chairman = CouncilMember(model_id="anthropic/claude-opus-4-5", name="Chair")

    with patch("synapse.council.orchestrator.asyncio.create_task"), _NO_THREAD, _NO_CONFLICT:
        result = await orchestrator.run(
            session_id=uuid.uuid4(),
            question="Solo question?",
            members=solo_member,
            chairman=chairman,
            context=context,
            db=mock_db,
            council_type="solo",
        )

    assert result.consensus_score == 1.0
    assert not result.dissent_detected


@pytest.mark.asyncio
async def test_orchestrator_single_member_bypasses_rank(orchestrator, mock_db, context):
    """council_type=llm but only one member — should also bypass Stage 2."""
    single = [CouncilMember(model_id="openai/gpt-4o", name="GPT")]
    chairman = CouncilMember(model_id="anthropic/claude-opus-4-5", name="Chair")

    with patch("synapse.council.orchestrator.asyncio.create_task"), _NO_THREAD, _NO_CONFLICT:
        result = await orchestrator.run(
            session_id=uuid.uuid4(),
            question="Q?",
            members=single,
            chairman=chairman,
            context=context,
            db=mock_db,
            council_type="llm",
        )

    assert result.consensus_score == 1.0


# ---------------------------------------------------------------------------
# Dissent detection
# ---------------------------------------------------------------------------


def test_detect_dissent_below_threshold(orchestrator, sample_ranking_result):
    sample_ranking_result.consensus_score = 0.3
    assert orchestrator._detect_dissent(sample_ranking_result) is True


def test_detect_dissent_above_threshold(orchestrator, sample_ranking_result):
    sample_ranking_result.consensus_score = 0.8
    assert orchestrator._detect_dissent(sample_ranking_result) is False


def test_detect_dissent_single_member(orchestrator, sample_ranking_result):
    sample_ranking_result.member_rankings = sample_ranking_result.member_rankings[:1]
    assert orchestrator._detect_dissent(sample_ranking_result) is False


# ---------------------------------------------------------------------------
# Precedent recall failure — should continue gracefully
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_orchestrator_continues_without_precedents(
    orchestrator, mock_db, two_members, chairman, context
):
    orchestrator._astrocyte.recall = AsyncMock(side_effect=Exception("Astrocyte unavailable"))

    with patch("synapse.council.orchestrator.asyncio.create_task"), _NO_THREAD, _NO_CONFLICT:
        result = await orchestrator.run(
            session_id=uuid.uuid4(),
            question="Q?",
            members=two_members,
            chairman=chairman,
            context=context,
            db=mock_db,
        )

    assert isinstance(result, CouncilResult)


@pytest.mark.asyncio
async def test_orchestrator_uses_council_review_memory_scope_and_skips_no_retain(
    orchestrator, mock_db, two_members, chairman, context
):
    contract = CouncilReviewRequest.model_validate(council_review_contract_fixture("approve"))

    with patch("synapse.council.orchestrator.asyncio.create_task"), _NO_THREAD, _NO_CONFLICT:
        result = await orchestrator.run(
            session_id=uuid.uuid4(),
            question="Fallback question",
            members=two_members,
            chairman=chairman,
            context=context,
            db=mock_db,
            council_type="llm",
            council_review=contract,
        )

    assert isinstance(result, CouncilResult)
    recall_kwargs = orchestrator._astrocyte.recall.call_args.kwargs
    assert recall_kwargs["tags"] == [
        f"workspace:{contract.workspace_id}",
        f"project:{contract.memory_scope.scope_id}",
    ]
    assert contract.proposed_action.summary in recall_kwargs["query"]

    await orchestrator._retain_to_astrocyte(
        session_id="session-1",
        question="Q?",
        stage1_responses=[],
        synthesis=MagicMock(verdict="Proceed.", confidence_label="medium"),
        consensus_score=1.0,
        council_type="llm",
        topic_tag="council_review",
        context=context,
        council_review=contract,
    )
    orchestrator._astrocyte.retain.assert_not_called()
