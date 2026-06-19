"""Council session CRUD helpers — thin layer over SQLAlchemy models."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from synapse.council.models import ContributeRequest, CouncilMember, CreateCouncilRequest
from synapse.db.models import CouncilSession, CouncilStatus


async def create_session(
    db: AsyncSession,
    request: CreateCouncilRequest,
    members: list[CouncilMember],
    chairman: CouncilMember,
    created_by: str,
    tenant_id: str | None = None,
) -> CouncilSession:
    """Insert a new CouncilSession and return it.

    Status is ``scheduled`` when ``request.run_at`` is set, otherwise ``pending``.
    Async-council fields (quorum, contribution_deadline) are persisted when present.
    """
    initial_status = CouncilStatus.scheduled if request.run_at else CouncilStatus.pending
    contribution_deadline = None
    if request.contribution_deadline_hours is not None:
        contribution_deadline = datetime.now(UTC) + timedelta(
            hours=request.contribution_deadline_hours
        )

    session = CouncilSession(
        id=uuid.uuid4(),
        question=request.question,
        status=initial_status,
        council_type=request.council_type,
        members=[m.model_dump() for m in members],
        chairman=chairman.model_dump(),
        config=request.config,
        topic_tag=request.topic_tag,
        template_id=request.template_id,
        created_by=created_by,
        tenant_id=tenant_id,
        quorum=request.quorum,
        contribution_deadline=contribution_deadline,
        run_at=request.run_at,
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return session


async def create_minimal_session(
    db: AsyncSession,
    *,
    tenant_id: str | None,
    created_by: str,
    question: str,
    title: str | None = None,
) -> CouncilSession:
    """Create a draft council from minimal inputs (used by the
    ``synapse_council_start`` chat tool).

    Skips template / member / chairman resolution — the caller (typically
    an LLM with only the user's question) doesn't know that context. The
    council lands in ``pending`` status with empty members/chairman; the
    user can promote it from the UI.

    Returns the persisted CouncilSession.
    """
    session = CouncilSession(
        id=uuid.uuid4(),
        question=question,
        status=CouncilStatus.pending,
        council_type="llm",
        members=[],
        chairman={},
        config={"title": title} if title else {},
        topic_tag=None,
        template_id=None,
        created_by=created_by,
        tenant_id=tenant_id,
        quorum=None,
        contribution_deadline=None,
        run_at=None,
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return session


async def add_contribution(
    db: AsyncSession,
    session_id: uuid.UUID,
    body: ContributeRequest,
    *,
    member_type: str = "human",
) -> CouncilSession:
    """Append a contribution to an async council session and return it."""
    session = await db.get(CouncilSession, session_id)
    if not session:
        raise ValueError(f"Session {session_id} not found")
    entry: dict[str, Any] = {
        "member_id": body.member_id,
        "member_name": body.member_name,
        "content": body.content,
        "member_type": member_type,
        "submitted_at": datetime.now(UTC).isoformat(),
    }
    # JSONB mutation — replace the list to trigger SQLAlchemy change detection
    session.contributions = [*session.contributions, entry]
    await db.commit()
    await db.refresh(session)
    return session


def quorum_met(session: CouncilSession) -> bool:
    """Return True when the session has enough contributions to proceed."""
    effective = session.quorum or len(session.members)
    return len(session.contributions) >= effective


async def get_session(
    db: AsyncSession,
    session_id: uuid.UUID,
    *,
    tenant_id: str | None | type(...) = ...,
) -> CouncilSession | None:
    """Fetch a council session by primary key.

    When ``tenant_id`` is provided (including ``None`` for a single-tenant
    JWT), the session is filtered through ``is_not_distinct_from`` and a
    cross-tenant row is returned as ``None`` — same shape as a missing
    row, so the caller's 404 path collapses both cases.

    The default sentinel ``...`` keeps the un-scoped call path (used by
    background workers, the orchestrator, audit emitters, etc.) which
    operates with a system identity rather than a user JWT.
    """
    stmt = (
        select(CouncilSession)
        .options(selectinload(CouncilSession.transcript))
        .where(CouncilSession.id == session_id)
    )
    result = await db.execute(stmt)
    session = result.scalar_one_or_none()
    if session is None:
        return None
    if tenant_id is ...:
        return session
    # Tenant-scoped fetch: collapse cross-tenant matches to "not found"
    # so the caller can't distinguish "exists in another tenant" (was 403)
    # from "doesn't exist" (404).
    if session.tenant_id != tenant_id:
        return None
    return session


async def list_sessions(
    db: AsyncSession,
    *,
    tenant_id: str | None = None,
    created_by: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> list[CouncilSession]:
    """Return sessions newest-first, optionally filtered by tenant / principal."""
    stmt = select(CouncilSession).order_by(desc(CouncilSession.created_at))
    if tenant_id is not None:
        stmt = stmt.where(CouncilSession.tenant_id == tenant_id)
    if created_by is not None:
        stmt = stmt.where(CouncilSession.created_by == created_by)
    stmt = stmt.limit(limit).offset(offset)
    result = await db.execute(stmt)
    return list(result.scalars().all())


async def mark_failed(
    db: AsyncSession,
    session_id: uuid.UUID,
    *,
    error: str | None = None,
) -> None:
    """Transition a council to ``failed`` and emit a ``council.failed`` audit event.

    Audit emit is best-effort and uses ``actor_principal="system"`` because
    failure paths are background tasks that may not have a user context.
    """
    from synapse.audit import emit as audit_emit

    session = await db.get(CouncilSession, session_id)
    if session:
        session.status = CouncilStatus.failed
        session.closed_at = datetime.now(UTC)
        if error:
            session.config = {**session.config, "_error": error}
        await audit_emit(
            db,
            "council.failed",
            "system",
            tenant_id=session.tenant_id,
            resource_type="council",
            resource_id=str(session_id),
            metadata={"error": (error or "")[:256], "created_by": session.created_by},
        )
        await db.commit()


async def approve_session(
    db: AsyncSession,
    session_id: uuid.UUID,
) -> CouncilSession | None:
    """Approve a council in pending_approval state and close it.

    No-ops if the session is already closed/failed or not in pending_approval.
    Returns the updated session, or None if not found.
    """
    session = await db.get(CouncilSession, session_id)
    if session and session.status == CouncilStatus.pending_approval:
        session.status = CouncilStatus.closed
        session.closed_at = datetime.now(UTC)
        await db.commit()
        await db.refresh(session)
    return session


async def close_session(
    db: AsyncSession,
    session_id: uuid.UUID,
    *,
    verdict: str | None = None,
) -> CouncilSession | None:
    """Close a session immediately with an optional verdict.

    Used by the MCP ``close`` tool when an agent wants to terminate an
    in-progress council and accept whatever deliberation has occurred so far.
    If the orchestrator finishes later it will overwrite the status — that is
    acceptable because a fully-synthesised verdict supersedes an early close.
    """
    session = await db.get(CouncilSession, session_id)
    if session and session.status not in (CouncilStatus.closed, CouncilStatus.failed):
        session.status = CouncilStatus.closed
        session.closed_at = datetime.now(UTC)
        if verdict:
            session.verdict = verdict
        await db.commit()
        await db.refresh(session)
    return session
