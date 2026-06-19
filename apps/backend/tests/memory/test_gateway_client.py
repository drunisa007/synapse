"""Tests for AstrocyteGatewayClient."""

from __future__ import annotations

import pytest
import respx
from httpx import AsyncClient, HTTPStatusError

from synapse.memory.context import AstrocyteContext
from synapse.memory.gateway_client import AstrocyteGatewayClient

BASE_URL = "http://astrocyte-mock"
API_KEY = "test-api-key"
CONTEXT = AstrocyteContext(principal="user-1", tenant_id="tenant-test")


@pytest.fixture
async def client():
    async with AsyncClient() as http:
        yield AstrocyteGatewayClient(base_url=BASE_URL, api_key=API_KEY, http_client=http)


# ---------------------------------------------------------------------------
# Headers
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_retain_sends_auth_headers():
    async with AsyncClient() as http:
        gw = AstrocyteGatewayClient(base_url=BASE_URL, api_key=API_KEY, http_client=http)

        with respx.mock(base_url=BASE_URL) as mock:
            mock.post("/v1/retain").respond(200, json={"memory_id": "mem-1", "stored": True})

            await gw.retain(
                content="Test content",
                bank_id="decisions",
                tags=["t1"],
                context=CONTEXT,
                metadata={},
            )

            request = mock.calls.last.request
            assert request.headers["x-api-key"] == API_KEY
            assert request.headers["x-astrocyte-principal"] == "user-1"


@pytest.mark.asyncio
async def test_retain_propagates_request_id_header():
    async with AsyncClient() as http:
        gw = AstrocyteGatewayClient(base_url=BASE_URL, api_key=API_KEY, http_client=http)

        with respx.mock(base_url=BASE_URL) as mock:
            mock.post("/v1/retain").respond(200, json={"memory_id": "mem-1", "stored": True})

            await gw.retain(
                content="Test content",
                bank_id="decisions",
                tags=["t1"],
                context=AstrocyteContext(
                    principal="user-1",
                    tenant_id="tenant-test",
                    request_id="creq-1",
                ),
                metadata={},
            )

            request = mock.calls.last.request
            assert request.headers["x-request-id"] == "creq-1"


@pytest.mark.asyncio
async def test_recall_returns_memory_hits():
    async with AsyncClient() as http:
        gw = AstrocyteGatewayClient(base_url=BASE_URL, api_key=API_KEY, http_client=http)

        hits_payload = [
            {
                "memory_id": "h1",
                "content": "Past ruling about X.",
                "score": 0.92,
                "bank_id": "precedents",
                "tags": [],
                "metadata": {},
            },
            {
                "memory_id": "h2",
                "content": "Prior decision about Y.",
                "score": 0.81,
                "bank_id": "precedents",
                "tags": [],
                "metadata": {},
            },
        ]
        with respx.mock(base_url=BASE_URL) as mock:
            mock.post("/v1/recall").respond(200, json={"memories": hits_payload})

            hits = await gw.recall(
                query="What about X?",
                bank_id="precedents",
                context=CONTEXT,
                max_results=5,
            )

    assert len(hits) == 2
    assert hits[0].memory_id == "h1"
    assert hits[0].score == pytest.approx(0.92)
    assert hits[1].content == "Prior decision about Y."


@pytest.mark.asyncio
async def test_recall_returns_empty_on_no_hits():
    async with AsyncClient() as http:
        gw = AstrocyteGatewayClient(base_url=BASE_URL, api_key=API_KEY, http_client=http)

        with respx.mock(base_url=BASE_URL) as mock:
            mock.post("/v1/recall").respond(200, json={"memories": []})

            hits = await gw.recall(
                query="obscure query",
                bank_id="precedents",
                context=CONTEXT,
            )

    assert hits == []


@pytest.mark.asyncio
async def test_retain_raises_on_http_error():
    async with AsyncClient() as http:
        gw = AstrocyteGatewayClient(base_url=BASE_URL, api_key=API_KEY, http_client=http)

        with respx.mock(base_url=BASE_URL) as mock:
            mock.post("/v1/retain").respond(500, json={"detail": "internal error"})

            with pytest.raises(HTTPStatusError):
                await gw.retain(
                    content="data",
                    bank_id="councils",
                    tags=[],
                    context=CONTEXT,
                    metadata={},
                )


@pytest.mark.asyncio
async def test_recall_payload_includes_bank_and_context():
    async with AsyncClient() as http:
        gw = AstrocyteGatewayClient(base_url=BASE_URL, api_key=API_KEY, http_client=http)

        with respx.mock(base_url=BASE_URL) as mock:
            mock.post("/v1/recall").respond(200, json={"memories": []})

            await gw.recall(
                query="question",
                bank_id="precedents",
                context=CONTEXT,
                max_results=3,
            )

            import json

            body = json.loads(mock.calls.last.request.content)
            assert body["bank_id"] == "precedents"
            assert body["query"] == "question"
            assert body["max_results"] == 3
