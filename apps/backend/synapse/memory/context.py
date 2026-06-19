"""AstrocyteContext construction from authenticated user."""

from __future__ import annotations

from dataclasses import dataclass

from synapse.auth.jwt import AuthenticatedUser


@dataclass(frozen=True)
class AstrocyteContext:
    """Passed to every Astrocyte gateway call for per-bank access control."""

    principal: str
    tenant_id: str | None = None
    request_id: str | None = None


def build_context(user: AuthenticatedUser) -> AstrocyteContext:
    return AstrocyteContext(principal=user.principal, tenant_id=user.tenant_id)


def system_context(sub: str = "synapse:system", tenant_id: str | None = None) -> AstrocyteContext:
    """Context for internal system calls (scheduled jobs, promotion, etc.)."""
    return AstrocyteContext(principal=sub, tenant_id=tenant_id)
