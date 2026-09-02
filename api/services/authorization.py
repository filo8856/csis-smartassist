"""Application-level role and permission authorization."""

from __future__ import annotations

from fastapi import HTTPException

from core.database import get_supabase_client


def extract_user_id(authorization: str) -> str:
    """Validate the existing Supabase JWT and return its authenticated user ID."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header.")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        return get_supabase_client().auth.get_user(token).user.id
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token.")


def get_user_roles(user_id: str) -> list[str]:
    result = (
        get_supabase_client()
        .table("user_roles")
        .select("roles(name)")
        .eq("user_id", user_id)
        .execute()
    )
    return [item["roles"]["name"] for item in (result.data or []) if item.get("roles")]


def get_user_permissions(user_id: str) -> list[str]:
    result = (
        get_supabase_client()
        .table("user_roles")
        .select("roles(role_permissions(permissions(name)))")
        .eq("user_id", user_id)
        .execute()
    )
    permissions: set[str] = set()
    for user_role in result.data or []:
        role = user_role.get("roles") or {}
        for mapping in role.get("role_permissions") or []:
            permission = mapping.get("permissions") or {}
            if permission.get("name"):
                permissions.add(permission["name"])
    return sorted(permissions)


def has_role(user_id: str, role: str) -> bool:
    return role in get_user_roles(user_id)


def has_permission(user_id: str, permission: str) -> bool:
    return permission in get_user_permissions(user_id)


def require_role(user_id: str, role: str) -> None:
    if not has_role(user_id, role):
        raise HTTPException(status_code=403, detail="Required role is missing.")


def require_permission(user_id: str, permission: str) -> None:
    if not has_permission(user_id, permission):
        raise HTTPException(status_code=403, detail=f"Permission required: {permission}.")


def get_user_ids_with_permission(permission: str) -> list[str]:
    result = (
        get_supabase_client()
        .table("user_roles")
        .select("user_id, roles(role_permissions(permissions(name)))")
        .execute()
    )
    user_ids: set[str] = set()
    for user_role in result.data or []:
        for mapping in (user_role.get("roles") or {}).get("role_permissions") or []:
            if (mapping.get("permissions") or {}).get("name") == permission:
                user_ids.add(user_role["user_id"])
    return list(user_ids)