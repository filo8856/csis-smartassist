"""Authenticated user and application-role management endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from core.database import get_supabase_client
from services.authorization import (
    extract_user_id,
    get_user_permissions,
    get_user_roles,
    has_role,
    require_permission,
)

router = APIRouter(prefix="/users", tags=["users"])


class RoleRequest(BaseModel):
    role: str


def _role_names(user_id: str) -> list[str]:
    return get_user_roles(user_id)


@router.get("/me/authorization")
async def get_my_authorization(authorization: str = Header(...)):
    user_id = extract_user_id(authorization)
    return {"roles": _role_names(user_id), "permissions": get_user_permissions(user_id)}


@router.get("")
async def list_users(authorization: str = Header(...)):
    requester_id = extract_user_id(authorization)
    require_permission(requester_id, "users.read")
    db = get_supabase_client()
    profiles = db.table("profiles").select("id, email, full_name, academic_role, department").execute()
    return [
        {**profile, "roles": _role_names(profile["id"])}
        for profile in (profiles.data or [])
    ]


@router.get("/{user_id}/roles")
async def get_roles_for_user(user_id: str, authorization: str = Header(...)):
    requester_id = extract_user_id(authorization)
    require_permission(requester_id, "users.read")
    return {"user_id": user_id, "roles": _role_names(user_id)}


@router.post("/{user_id}/roles")
async def assign_role(
    user_id: str,
    body: RoleRequest,
    authorization: str = Header(...),
):
    requester_id = extract_user_id(authorization)
    require_permission(requester_id, "users.roles.manage")
    if requester_id == user_id:
        raise HTTPException(status_code=400, detail="Users cannot modify their own roles.")
    if body.role == "super_admin" and not has_role(requester_id, "super_admin"):
        raise HTTPException(status_code=403, detail="Only a super admin can assign super_admin.")

    db = get_supabase_client()
    role = db.table("roles").select("id, name").eq("name", body.role).single().execute()
    if not role.data:
        raise HTTPException(status_code=404, detail="Role not found.")
    try:
        result = db.table("user_roles").insert({"user_id": user_id, "role_id": role.data["id"]}).execute()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Unable to assign role.") from exc
    return {"user_id": user_id, "role": body.role, "data": result.data}


@router.delete("/{user_id}/roles/{role}")
async def remove_role(
    user_id: str,
    role: str,
    authorization: str = Header(...),
):
    requester_id = extract_user_id(authorization)
    require_permission(requester_id, "users.roles.manage")
    if requester_id == user_id:
        raise HTTPException(status_code=400, detail="Users cannot modify their own roles.")

    db = get_supabase_client()
    role_result = db.table("roles").select("id").eq("name", role).single().execute()
    if not role_result.data:
        raise HTTPException(status_code=404, detail="Role not found.")
    result = (
        db.table("user_roles")
        .delete()
        .eq("user_id", user_id)
        .eq("role_id", role_result.data["id"])
        .execute()
    )
    return {"user_id": user_id, "role": role, "removed": bool(result.data)}