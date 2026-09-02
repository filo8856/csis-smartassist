import asyncio
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from services.authorization import (
    get_user_permissions,
    get_user_roles,
    has_permission,
    require_permission,
)


def test_multiple_roles_are_combined_into_unique_permissions():
    client = MagicMock()
    client.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[
            {"roles": {"name": "faculty", "role_permissions": [{"permissions": {"name": "faculty.read"}}, {"permissions": {"name": "department.read"}}]}},
            {"roles": {"name": "booking_admin", "role_permissions": [{"permissions": {"name": "bookings.approve"}}, {"permissions": {"name": "department.read"}}]}},
        ]
    )

    with patch("services.authorization.get_supabase_client", return_value=client):
        assert get_user_roles("user-1") == ["faculty", "booking_admin"]
        assert get_user_permissions("user-1") == [
            "bookings.approve",
            "department.read",
            "faculty.read",
        ]


def test_permission_check_does_not_cross_role_boundaries():
    with patch("services.authorization.get_user_permissions", return_value=["bookings.approve"]):
        assert has_permission("user-1", "bookings.approve")
        assert not has_permission("user-1", "rag.write")
        with pytest.raises(HTTPException) as error:
            require_permission("user-1", "rag.write")
        assert error.value.status_code == 403


def test_role_management_rejects_self_assignment():
    with patch("routes.users.extract_user_id", return_value="user-1"), patch(
        "routes.users.require_permission"
    ) as require:
        from routes.users import RoleRequest, assign_role

        with pytest.raises(HTTPException) as error:
            asyncio.run(assign_role("user-1", RoleRequest(role="super_admin"), "Bearer token"))
        assert error.value.status_code == 400
        require.assert_called_once_with("user-1", "users.roles.manage")