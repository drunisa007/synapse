"""Astrocyte gateway HTTP client — retain / recall / reflect / forget."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

import httpx

from synapse.memory.context import AstrocyteContext

_logger = logging.getLogger(__name__)


@dataclass
class MemoryHit:
    memory_id: str
    content: str
    score: float
    bank_id: str
    tags: list[str]
    metadata: dict[str, Any]


@dataclass
class RetainResult:
    memory_id: str
    stored: bool


@dataclass
class ReflectResult:
    answer: str
    sources: list[dict[str, Any]]


@dataclass
class GraphEntity:
    entity_id: str
    name: str
    entity_type: str
    metadata: dict[str, Any]


class AstrocyteGatewayClient:
    """Thin async HTTP wrapper over the Astrocyte gateway REST API."""

    def __init__(
        self,
        base_url: str,
        api_key: str,
        http_client: httpx.AsyncClient,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._http = http_client

    def _headers(self, context: AstrocyteContext) -> dict[str, str]:
        """Build headers for api_key auth mode: X-Api-Key + X-Astrocyte-Principal."""
        headers = {
            "X-Api-Key": self._api_key,
            "X-Astrocyte-Principal": context.principal,
            "Content-Type": "application/json",
        }
        if context.request_id:
            headers["X-Request-Id"] = context.request_id
        return headers

    async def retain(
        self,
        content: str,
        bank_id: str,
        tags: list[str],
        context: AstrocyteContext,
        metadata: dict[str, Any] | None = None,
    ) -> RetainResult:
        payload: dict[str, Any] = {"content": content, "bank_id": bank_id, "tags": tags}
        if metadata:
            payload["metadata"] = metadata

        resp = await self._http.post(
            f"{self._base_url}/v1/retain",
            json=payload,
            headers=self._headers(context),
        )
        resp.raise_for_status()
        data = resp.json()
        return RetainResult(
            memory_id=data.get("memory_id", ""),
            stored=data.get("stored", True),
        )

    async def recall(
        self,
        query: str,
        bank_id: str,
        context: AstrocyteContext,
        max_results: int = 5,
        max_tokens: int | None = None,
        tags: list[str] | None = None,
    ) -> list[MemoryHit]:
        payload: dict[str, Any] = {
            "query": query,
            "bank_id": bank_id,
            "max_results": max_results,
        }
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens
        if tags:
            payload["tags"] = tags

        resp = await self._http.post(
            f"{self._base_url}/v1/recall",
            json=payload,
            headers=self._headers(context),
        )
        resp.raise_for_status()
        data = resp.json()

        hits = []
        for h in data.get("memories", []):
            hits.append(
                MemoryHit(
                    memory_id=h.get("memory_id", ""),
                    content=h.get("content", ""),
                    score=h.get("score", 0.0),
                    bank_id=h.get("bank_id", bank_id),
                    tags=h.get("tags", []),
                    metadata=h.get("metadata", {}),
                )
            )
        return hits

    async def reflect(
        self,
        query: str,
        bank_id: str,
        context: AstrocyteContext,
        max_tokens: int | None = None,
        include_sources: bool = True,
    ) -> ReflectResult:
        payload: dict[str, Any] = {
            "query": query,
            "bank_id": bank_id,
            "include_sources": include_sources,
        }
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens

        resp = await self._http.post(
            f"{self._base_url}/v1/reflect",
            json=payload,
            headers=self._headers(context),
        )
        resp.raise_for_status()
        data = resp.json()
        return ReflectResult(
            answer=data.get("answer", ""),
            sources=data.get("sources", []),
        )

    async def forget_principal(
        self,
        principal: str,
        context: AstrocyteContext,
        *,
        tenant_id: str | None = None,
    ) -> dict[str, Any]:
        """DSAR right-to-erasure: erase all memory rows tagged
        ``principal:{principal}`` across the tenant's banks.

        POSTs to Astrocyte's ``/v1/dsar/forget_principal`` (shipped in
        Astrocyte ≥ v0.10). Returns the gateway's report:

            {"banks_processed": int, "memories_deleted": int,
             "details": [{"bank": "...", "deleted": int}, ...]}

        Raises:
          * ``NotImplementedError`` — gateway returned 404 or 501,
            meaning the published Astrocyte image lags this Synapse
            version. Operators should pin to a known-good tag (see
            ``cerebro/docs/_design/deployment-modes.md`` §4.1) or build
            from local source. Synapse-side erasure has already
            completed; the certificate records this as
            ``astrocyte_pending``.
          * ``httpx.HTTPStatusError`` — any other non-2xx status. The
            worker catches this and records the action as ``failed``.
        """
        payload: dict[str, Any] = {"principal": principal}
        if tenant_id is not None:
            payload["tenant_id"] = tenant_id

        resp = await self._http.post(
            f"{self._base_url}/v1/dsar/forget_principal",
            json=payload,
            headers=self._headers(context),
        )
        if resp.status_code in (404, 501):
            raise NotImplementedError(
                f"Astrocyte gateway does not expose /v1/dsar/forget_principal "
                f"(status {resp.status_code}). Upgrade to Astrocyte >= v0.10."
            )
        resp.raise_for_status()
        return resp.json()

    async def forget(
        self,
        bank_id: str,
        context: AstrocyteContext,
        memory_ids: list[str] | None = None,
        tags: list[str] | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {"bank_id": bank_id}
        if memory_ids:
            payload["memory_ids"] = memory_ids
        if tags:
            payload["tags"] = tags

        resp = await self._http.post(
            f"{self._base_url}/v1/forget",
            json=payload,
            headers=self._headers(context),
        )
        resp.raise_for_status()
        return resp.json()

    async def compile(
        self,
        bank_id: str,
        context: AstrocyteContext,
        scope: str | None = None,
    ) -> dict[str, Any]:
        """Trigger wiki synthesis for a bank (M8 compile pipeline)."""
        payload: dict[str, Any] = {"bank_id": bank_id}
        if scope is not None:
            payload["scope"] = scope

        resp = await self._http.post(
            f"{self._base_url}/v1/compile",
            json=payload,
            headers=self._headers(context),
        )
        resp.raise_for_status()
        return resp.json()

    async def graph_search(
        self,
        query: str,
        bank_id: str,
        context: AstrocyteContext,
        limit: int = 10,
    ) -> list[GraphEntity]:
        """Search the knowledge graph for entities matching a name query."""
        payload: dict[str, Any] = {"query": query, "bank_id": bank_id, "limit": limit}

        resp = await self._http.post(
            f"{self._base_url}/v1/graph/search",
            json=payload,
            headers=self._headers(context),
        )
        resp.raise_for_status()
        data = resp.json()

        return [
            GraphEntity(
                entity_id=e.get("entity_id", ""),
                name=e.get("name", ""),
                entity_type=e.get("entity_type", ""),
                metadata=e.get("metadata", {}),
            )
            for e in data.get("entities", [])
        ]

    async def graph_neighbors(
        self,
        entity_ids: list[str],
        bank_id: str,
        context: AstrocyteContext,
        max_depth: int = 2,
        limit: int = 20,
    ) -> list[MemoryHit]:
        """Traverse the knowledge graph from seed entity IDs."""
        payload: dict[str, Any] = {
            "entity_ids": entity_ids,
            "bank_id": bank_id,
            "max_depth": max_depth,
            "limit": limit,
        }

        resp = await self._http.post(
            f"{self._base_url}/v1/graph/neighbors",
            json=payload,
            headers=self._headers(context),
        )
        resp.raise_for_status()
        data = resp.json()

        return [
            MemoryHit(
                memory_id=h.get("memory_id", ""),
                content=h.get("content", ""),
                score=h.get("score", 0.0),
                bank_id=h.get("bank_id", bank_id),
                tags=h.get("tags", []),
                metadata=h.get("metadata", {}),
            )
            for h in data.get("hits", [])
        ]
