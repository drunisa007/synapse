"""Tests for the /v1/councils router."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from synapse.db.models import CouncilSession, CouncilStatus
from synapse.main import create_app
from tests.conftest import TEST_SETTINGS, make_jwt
from tests.council_review_fixtures import (
    assert_no_forbidden_contract_fixture_fragments,
    council_review_contract_fixture,
    council_review_fixture,
)

# ---------------------------------------------------------------------------
# App fixture with fully mocked infrastructure
# ---------------------------------------------------------------------------


@pytest.fixture
def _wired_client(mock_astrocyte, mock_centrifugo, mock_llm):
    """App + TestClient with mocks applied *after* lifespan runs.

    Lifespan overwrites app.state — we must patch synapse.main.get_settings so
    it uses TEST_SETTINGS, then override astrocyte/centrifugo/sessionmaker after
    the lifespan yields.
    """
    application = create_app()
    mock_session = AsyncMock()
    mock_sessionmaker = MagicMock()
    mock_sessionmaker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_sessionmaker.return_value.__aexit__ = AsyncMock(return_value=None)

    with (
        patch("synapse.main.get_settings", return_value=TEST_SETTINGS),
        TestClient(application, raise_server_exceptions=False) as c,
    ):
        # Lifespan has run with TEST_SETTINGS — now inject test doubles
        application.state.astrocyte = mock_astrocyte
        application.state.centrifugo = mock_centrifugo
        application.state.sessionmaker = mock_sessionmaker
        yield c, mock_session


@pytest.fixture
def client(_wired_client):
    c, _ = _wired_client
    return c


@pytest.fixture
def db_session(_wired_client):
    _, session = _wired_client
    return session


@pytest.fixture
def token():
    return make_jwt(sub="user-1", tenant_id="tenant-test")


@pytest.fixture
def headers(token):
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_thread_event(id: int = 1, thread_id: uuid.UUID | None = None) -> MagicMock:
    e = MagicMock()
    e.id = id
    e.thread_id = thread_id or uuid.uuid4()
    e.event_type = "council_started"
    e.actor_id = "system"
    e.actor_name = ""
    e.content = None
    e.event_metadata = {}
    e.created_at = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)
    return e


def _make_council_session(**kwargs) -> CouncilSession:
    defaults = dict(
        id=uuid.uuid4(),
        question="What should we do?",
        status=CouncilStatus.closed,
        council_type="llm",
        members=[{"model_id": "openai/gpt-4o", "name": "GPT"}],
        chairman={"model_id": "anthropic/claude-opus-4-5", "name": "Chair"},
        config={},
        verdict="Proceed with plan A.",
        consensus_score=0.85,
        confidence_label="high",
        dissent_detected=False,
        topic_tag="product",
        template_id=None,
        created_by="user:user-1",
        tenant_id="tenant-test",
        created_at=datetime.now(UTC),
        closed_at=datetime.now(UTC),
    )
    defaults.update(kwargs)
    obj = MagicMock(spec=CouncilSession)
    for k, v in defaults.items():
        setattr(obj, k, v)
    return obj


def _make_council_transcript_from_agent_positions(agent_positions: list[dict]):
    transcript = MagicMock()
    stage1_responses = []
    aggregate_scores = {}
    for index, position in enumerate(agent_positions):
        response_label = f"Response {chr(65 + index)}"
        stage1_responses.append(
            {
                "member_id": f"openai/gpt-4o-internal-{index + 1}",
                "member_name": position.get("agent_label", ""),
                "content": position.get("summary", ""),
                "confidence_label": position.get("confidence_label", ""),
            }
        )
        aggregate_scores[response_label] = float(position.get("rank") or index + 1)
    transcript.stage1_responses = stage1_responses
    transcript.aggregate_scores = aggregate_scores
    return transcript


def _council_review_payload() -> dict:
    return council_review_contract_fixture("approve")


@pytest.mark.parametrize(
    "fixture_name",
    ["approve", "reject", "timeout", "unavailable_review_needed"],
)
def test_council_review_contract_fixtures_validate(fixture_name):
    fixture = council_review_fixture(fixture_name)

    assert fixture["schema_version"] == "council_review_fixture.v1"
    assert fixture["expected_ui_status"] in {
        "Approved",
        "Rejected",
        "Needs human review",
    }
    assert_no_forbidden_contract_fixture_fragments(fixture)


# ---------------------------------------------------------------------------
# POST /v1/councils
# ---------------------------------------------------------------------------


def test_create_council_returns_202(client, db_session, headers):
    session_id = uuid.uuid4()
    thread_id = uuid.uuid4()
    mock_cs = _make_council_session(id=session_id, status=CouncilStatus.pending)
    mock_thread = MagicMock()
    mock_thread.id = thread_id

    with (
        patch("synapse.routers.councils.asyncio.create_task"),
        patch("synapse.council.session.create_session", new=AsyncMock(return_value=mock_cs)),
        patch("synapse.routers.councils.create_thread", new=AsyncMock(return_value=mock_thread)),
        patch(
            "synapse.routers.councils.append_event",
            new=AsyncMock(return_value=_make_thread_event(thread_id=thread_id)),
        ),
    ):
        resp = client.post(
            "/v1/councils",
            json={"question": "What should we prioritise?"},
            headers=headers,
        )

    assert resp.status_code == 202
    body = resp.json()
    assert "session_id" in body
    assert "thread_id" in body
    assert body["status"] == CouncilStatus.pending


def test_create_council_requires_auth(client):
    resp = client.post("/v1/councils", json={"question": "Q?"})
    assert resp.status_code == 401


def test_create_council_accepts_settings_alias_for_config(client, db_session, headers):
    """`settings` is the canonical wire field for the council config map
    (Cerebro's name); Synapse accepts it as an alias for the legacy
    `config` field. Both names must reach `request.config` internally.
    """
    captured: dict = {}

    async def fake_create_session(**kwargs):
        captured["config"] = kwargs["request"].config
        captured["council_type"] = kwargs["request"].council_type
        return _make_council_session(id=uuid.uuid4(), status=CouncilStatus.pending)

    mock_thread = MagicMock()
    mock_thread.id = uuid.uuid4()

    with (
        patch("synapse.routers.councils.asyncio.create_task"),
        patch(
            "synapse.routers.councils.create_session",
            new=AsyncMock(side_effect=fake_create_session),
        ),
        patch("synapse.routers.councils.create_thread", new=AsyncMock(return_value=mock_thread)),
        patch(
            "synapse.routers.councils.append_event",
            new=AsyncMock(return_value=_make_thread_event(thread_id=mock_thread.id)),
        ),
    ):
        resp = client.post(
            "/v1/councils",
            json={
                "question": "Q?",
                "settings": {"mode": "deliberation", "x": 1},
            },
            headers=headers,
        )

    assert resp.status_code == 202
    assert captured["config"] == {"mode": "deliberation", "x": 1}


def test_create_council_accepts_council_review_payload(client, db_session, headers):
    captured: dict = {}
    contract_fixture = _council_review_payload()

    async def fake_create_session(**kwargs):
        captured["request"] = kwargs["request"]
        return _make_council_session(id=uuid.uuid4(), status=CouncilStatus.pending)

    mock_thread = MagicMock()
    mock_thread.id = uuid.uuid4()
    create_thread_mock = AsyncMock(return_value=mock_thread)
    append_event_mock = AsyncMock(return_value=_make_thread_event(thread_id=mock_thread.id))
    audit_emit_mock = AsyncMock()

    with (
        patch("synapse.routers.councils.asyncio.create_task"),
        patch(
            "synapse.routers.councils.create_session",
            new=AsyncMock(side_effect=fake_create_session),
        ),
        patch("synapse.routers.councils.create_thread", new=create_thread_mock),
        patch("synapse.routers.councils.append_event", new=append_event_mock),
        patch("synapse.routers.councils.audit_emit", new=audit_emit_mock),
    ):
        resp = client.post(
            "/v1/councils",
            json={
                "question": "transport fallback prompt",
                "council_type": "llm",
                "topic_tag": "council_review",
                "settings": {"council_review": contract_fixture},
            },
            headers={**headers, "X-Request-Id": contract_fixture["request_id"]},
        )

    assert resp.status_code == 202
    request = captured["request"]
    contract = request.config["council_review"]
    assert contract["contract_version"] == "council_review.v1"
    assert contract["workspace_id"] == contract_fixture["workspace_id"]
    assert contract["actor_id"] == contract_fixture["actor_id"]
    assert contract["request_id"] == contract_fixture["request_id"]
    assert contract_fixture["proposed_action"]["summary"] in request.question
    assert "Selected context summary" in request.question
    assert "transport fallback prompt" not in request.question
    assert (
        create_thread_mock.call_args.kwargs["title"] == contract_fixture["proposed_action"]["title"]
    )
    audit_metadata = audit_emit_mock.call_args.kwargs["metadata"]
    assert "question_preview" not in audit_metadata
    assert audit_metadata["request_id_hash"] != contract_fixture["request_id"]
    assert contract_fixture["request_id"] not in str(audit_metadata)
    started_metadata = append_event_mock.call_args.kwargs["metadata"]
    assert "question" not in started_metadata
    assert started_metadata["request_id_hash"] == audit_metadata["request_id_hash"]
    assert contract_fixture["proposed_action"]["summary"] not in str(started_metadata)


def test_create_council_promotes_settings_mode_red_team_to_council_type(
    client, db_session, headers
):
    """`settings.mode == "red_team"` is the canonical Cerebro-parity opt-in.
    Synapse's orchestrator branches on top-level `council_type`, so the
    create endpoint promotes the mode into that field automatically.
    """
    captured: dict = {}

    async def fake_create_session(**kwargs):
        captured["council_type"] = kwargs["request"].council_type
        return _make_council_session(id=uuid.uuid4(), status=CouncilStatus.pending)

    mock_thread = MagicMock()
    mock_thread.id = uuid.uuid4()

    with (
        patch("synapse.routers.councils.asyncio.create_task"),
        patch(
            "synapse.routers.councils.create_session",
            new=AsyncMock(side_effect=fake_create_session),
        ),
        patch("synapse.routers.councils.create_thread", new=AsyncMock(return_value=mock_thread)),
        patch(
            "synapse.routers.councils.append_event",
            new=AsyncMock(return_value=_make_thread_event(thread_id=mock_thread.id)),
        ),
    ):
        resp = client.post(
            "/v1/councils",
            json={"question": "Q?", "settings": {"mode": "red_team"}},
            headers=headers,
        )

    assert resp.status_code == 202
    assert captured["council_type"] == "red_team"


def test_create_council_does_not_override_explicit_council_type(client, db_session, headers):
    """If the caller already passes `council_type` explicitly, the mode-
    promotion logic must not overwrite it. (Belt-and-braces for clients
    that send both during the deprecation window.)
    """
    captured: dict = {}

    async def fake_create_session(**kwargs):
        captured["council_type"] = kwargs["request"].council_type
        return _make_council_session(id=uuid.uuid4(), status=CouncilStatus.pending)

    mock_thread = MagicMock()
    mock_thread.id = uuid.uuid4()

    with (
        patch("synapse.routers.councils.asyncio.create_task"),
        patch(
            "synapse.routers.councils.create_session",
            new=AsyncMock(side_effect=fake_create_session),
        ),
        patch("synapse.routers.councils.create_thread", new=AsyncMock(return_value=mock_thread)),
        patch(
            "synapse.routers.councils.append_event",
            new=AsyncMock(return_value=_make_thread_event(thread_id=mock_thread.id)),
        ),
    ):
        resp = client.post(
            "/v1/councils",
            json={
                "question": "Q?",
                "council_type": "async",  # explicit, must win
                "settings": {"mode": "red_team"},
            },
            headers=headers,
        )

    assert resp.status_code == 202
    # `async` is preserved — the mode-promotion only fires when the caller
    # left council_type at the default "llm".
    assert captured["council_type"] == "async"


def test_create_council_validates_question(client, headers):
    resp = client.post("/v1/councils", json={}, headers=headers)
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# GET /v1/councils/{session_id}
# ---------------------------------------------------------------------------


def test_get_council_returns_session(client, db_session, headers):
    session_id = uuid.uuid4()
    mock_cs = _make_council_session(id=session_id)
    db_session.get = AsyncMock(return_value=mock_cs)

    with patch("synapse.routers.councils.get_session", new=AsyncMock(return_value=mock_cs)):
        resp = client.get(f"/v1/councils/{session_id}", headers=headers)

    assert resp.status_code == 200
    body = resp.json()
    assert body["session_id"] == str(session_id)
    assert body["verdict"] == "Proceed with plan A."


@pytest.mark.parametrize("fixture_name", ["approve", "reject"])
def test_get_council_returns_shared_council_review_response(
    client, db_session, headers, fixture_name
):
    fixture = council_review_fixture(fixture_name)
    contract_fixture = fixture["request"]
    synapse_response = fixture["synapse_get_response"]
    agent_positions = synapse_response["council_review_response"]["agent_positions"]
    session_id = uuid.uuid4()
    mock_cs = _make_council_session(
        id=session_id,
        status=CouncilStatus.closed,
        config={"council_review": contract_fixture},
        verdict=synapse_response["verdict"],
        confidence_label=synapse_response["confidence_label"],
        dissent_detected=synapse_response["dissent_detected"],
        conflict_metadata={},
        transcript=_make_council_transcript_from_agent_positions(agent_positions),
        created_at=datetime.fromisoformat(synapse_response["created_at"]),
        closed_at=datetime.fromisoformat(synapse_response["closed_at"]),
    )
    db_session.get = AsyncMock(return_value=mock_cs)

    with patch("synapse.routers.councils.get_session", new=AsyncMock(return_value=mock_cs)):
        resp = client.get(f"/v1/councils/{session_id}", headers=headers)

    assert resp.status_code == 200
    body = resp.json()
    assert body["session_id"] == str(session_id)
    assert body["verdict"] == synapse_response["verdict"]
    review = body["council_review_response"]
    assert review == synapse_response["council_review_response"]
    assert "review_id" not in review
    assert "openai/gpt-4o-internal" not in str(review)


def test_get_council_404_on_missing(client, db_session, headers):
    session_id = uuid.uuid4()
    with patch("synapse.routers.councils.get_session", new=AsyncMock(return_value=None)):
        resp = client.get(f"/v1/councils/{session_id}", headers=headers)
    assert resp.status_code == 404


def test_get_council_403_on_wrong_tenant(client, headers):
    session_id = uuid.uuid4()
    mock_cs = _make_council_session(id=session_id, tenant_id="other-tenant")
    with patch("synapse.routers.councils.get_session", new=AsyncMock(return_value=mock_cs)):
        resp = client.get(f"/v1/councils/{session_id}", headers=headers)
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# GET /v1/councils
# ---------------------------------------------------------------------------


def test_list_councils_returns_list(client, headers):
    sessions = [
        _make_council_session(id=uuid.uuid4()),
        _make_council_session(id=uuid.uuid4()),
    ]
    with patch("synapse.routers.councils.list_sessions", new=AsyncMock(return_value=sessions)):
        resp = client.get("/v1/councils", headers=headers)

    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body, list)
    assert len(body) == 2
    # Summary should truncate long questions
    for item in body:
        assert "session_id" in item
        assert "status" in item


def test_list_councils_requires_auth(client):
    resp = client.get("/v1/councils")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# GET /v1/centrifugo/token
# ---------------------------------------------------------------------------


def test_centrifugo_token_returns_token(client, headers):
    resp = client.get("/v1/centrifugo/token", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert "token" in body
    assert isinstance(body["token"], str)


def test_centrifugo_token_requires_auth(client):
    resp = client.get("/v1/centrifugo/token")
    assert resp.status_code == 401
