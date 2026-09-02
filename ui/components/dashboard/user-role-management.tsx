"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { ManagedUser } from "@/lib/types";
import styles from "./user-role-management.module.scss";

const ROLE_OPTIONS = [
  "student",
  "faculty",
  "booking_admin",
  "content_admin",
  "department_admin",
  "super_admin",
];

export default function UserRoleManagement() {
  const [users, setUsers] = useState<ManagedUser[]>([]);
  const [selectedRole, setSelectedRole] = useState("student");
  const [loading, setLoading] = useState(true);

  const loadUsers = async () => {
    setLoading(true);
    try {
      setUsers(await api.listUsers());
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadUsers();
  }, []);

  const assignRole = async (userId: string) => {
    await api.assignRole(userId, selectedRole);
    await loadUsers();
  };

  const removeRole = async (userId: string, role: string) => {
    await api.removeRole(userId, role);
    await loadUsers();
  };

  if (loading) return <p className={styles.status}>Loading users...</p>;

  return (
    <div className={styles.panel}>
      <div className={styles.toolbar}>
        <label htmlFor="role-to-assign">Role</label>
        <select id="role-to-assign" value={selectedRole} onChange={(event) => setSelectedRole(event.target.value)}>
          {ROLE_OPTIONS.map((role) => <option key={role}>{role}</option>)}
        </select>
      </div>
      <div className={styles.list}>
        {users.map((managedUser) => (
          <div className={styles.user} key={managedUser.id}>
            <div>
              <strong>{managedUser.full_name || managedUser.email}</strong>
              <span>{managedUser.email}</span>
              <div className={styles.roles}>
                {managedUser.roles.map((role) => (
                  <button key={role} className={styles.role} onClick={() => void removeRole(managedUser.id, role)} title={`Remove ${role}`}>
                    {role} x
                  </button>
                ))}
              </div>
            </div>
            <button className={styles.assign} onClick={() => void assignRole(managedUser.id)}>Assign role</button>
          </div>
        ))}
      </div>
    </div>
  );
}