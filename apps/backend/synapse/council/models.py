"""Pydantic models for council requests, responses, and in-flight state."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import AliasChoices, BaseModel, ConfigDict, Field


class CouncilMember(BaseModel):
    model_id: str
    name: str = ""  # derived from model_id if empty
    role: str = ""  # injected into system prompt
    system_prompt_override: str = ""  # replaces default system prompt if set
    member_type: Literal["llm", "human"] = "llm"  # B3: human members contribute via API


class CreateCouncilRequest(BaseModel):
    # Allow both the internal Python attribute name (`config`) and the
    # canonical wire field (`settings`) on input. Cerebro's create payload
    # uses `settings`; Synapse historically used `config`. Accepting both
    # via `validation_alias` lets one client payload target either backend.
    model_config = ConfigDict(populate_by_name=True)

    question: str
    members: list[CouncilMember] | None = None  # uses defaults if None
    chairman: CouncilMember | None = None  # uses default if None
    council_type: str = "llm"
    template_id: str | None = None
    topic_tag: str | None = None
    # Wire name: `settings` (canonical) or `config` (legacy alias).
    # Internal attribute name stays `config` to avoid touching every caller.
    config: dict[str, Any] = Field(
        default_factory=dict,
        validation_alias=AliasChoices("config", "settings"),
    )
    # B3 — async councils
    quorum: int | None = None  # min contributions before Stage 2 fires; None = all members
    contribution_deadline_hours: float | None = None  # forced resume after N hours
    # B7 — scheduled councils
    run_at: datetime | None = None  # UTC timestamp to start; None = immediate


class CouncilReviewSelectedContextSummary(BaseModel):
    detail_level: str | None = None
    availability: str | None = None
    summary: dict[str, Any] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)


class CouncilReviewContextRef(BaseModel):
    kind: str
    id: str | None = None
    label: str | None = None
    metadata: dict[str, str] = Field(default_factory=dict)


class CouncilReviewProposedAction(BaseModel):
    kind: str
    title: str | None = None
    summary: str | None = None
    goal: str | None = None
    decision_kind: str | None = None
    proposal_ids: list[str] = Field(default_factory=list)
    scenario_ids: list[str] = Field(default_factory=list)
    context_ref: CouncilReviewContextRef | None = None


class CouncilReviewRiskSignals(BaseModel):
    risk_level: str | None = None
    confidence_label: str | None = None
    warnings: list[str] = Field(default_factory=list)
    requires_human_review: bool = False


class CouncilReviewMemoryScope(BaseModel):
    workspace_id: str
    scope_kind: str
    scope_id: str
    retention: str


class CouncilReviewRequest(BaseModel):
    contract_version: str
    workspace_id: str
    actor_id: str
    request_id: str
    source: str
    mode: str
    template: str | None = None
    selected_context_summaries: list[CouncilReviewSelectedContextSummary] = Field(
        default_factory=list
    )
    proposed_action: CouncilReviewProposedAction
    risk_signals: CouncilReviewRiskSignals
    memory_scope: CouncilReviewMemoryScope
    retention: str


class CouncilReviewAgentPosition(BaseModel):
    agent_id: str | None = None
    agent_label: str
    position: str
    confidence_label: str | None = None
    summary: str
    dissent: bool = False
    rank: int | None = None


class CouncilReviewResponse(BaseModel):
    contract_version: str
    workspace_id: str
    actor_id: str
    request_id: str
    mode: str
    review_id: str | None = None
    status: str
    stage: str
    selected_context_summaries: list[CouncilReviewSelectedContextSummary] = Field(
        default_factory=list
    )
    proposed_action: CouncilReviewProposedAction
    recommendation: str
    summary: str
    confidence_label: str
    rationale: list[str] = Field(default_factory=list)
    risks: list[str] = Field(default_factory=list)
    dissent: list[str] = Field(default_factory=list)
    agent_positions: list[CouncilReviewAgentPosition] = Field(default_factory=list)
    risk_signals: CouncilReviewRiskSignals
    memory_scope: CouncilReviewMemoryScope
    updated_at: str | None = None


class ContributeRequest(BaseModel):
    """Body for POST /v1/councils/{id}/contribute (B3)."""

    member_id: str  # identifies the human participant (e.g. "user:alice")
    member_name: str
    content: str


class StageOneResponse(BaseModel):
    member_id: str  # e.g. "openai/gpt-4o"
    member_name: str
    content: str
    error: str | None = None


class MemberRanking(BaseModel):
    member_id: str
    member_name: str
    ranking: list[str]  # ordered labels: ["Response B", "Response A", "Response C"]
    raw_response: str


class RankingResult(BaseModel):
    label_map: dict[str, str]  # {"Response A": "member_id", ...}
    member_rankings: list[MemberRanking]
    aggregate_scores: dict[str, float]  # {"Response A": 1.67, ...}  (lower = better rank)
    consensus_score: float  # Kendall's W [0, 1]


class SynthesisResult(BaseModel):
    verdict: str
    confidence_label: str  # high | medium | low
    uncertainty_markers: list[str] = Field(default_factory=list)


class ConflictResult(BaseModel):
    detected: bool
    summary: str | None = None  # LLM-generated explanation of the conflict
    conflicting_content: str | None = None  # the precedent text that conflicts
    precedent_score: float | None = None  # similarity score of the conflicting precedent


class MemberCritique(BaseModel):
    member_id: str
    member_name: str
    critique: str
    error: str | None = None


class DeliberationRound(BaseModel):
    round: int
    critiques: list[MemberCritique]
    revised_responses: list[StageOneResponse]
    converged: bool = False


class CouncilResult(BaseModel):
    session_id: uuid.UUID
    question: str
    verdict: str
    consensus_score: float
    confidence_label: str
    dissent_detected: bool
    stage1_responses: list[StageOneResponse]  # final-round responses going into ranking
    ranking_result: RankingResult
    synthesis: SynthesisResult
    deliberation_rounds: list[DeliberationRound] = Field(default_factory=list)
