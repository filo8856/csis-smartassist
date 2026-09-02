"use client";

/**
 * Admin Page — Department management dashboard.
 *
 * Two-tab interface:
 * 1. Booking Approval Matrix — review and approve/reject booking requests
 * 2. RAG Pipeline Dashboard — sync knowledge base from Google Drive
 *
 * Sections are restricted by application permissions.
 */

import { useEffect, useState } from "react";
import { useAuth } from "@/lib/hooks/useAuth";
import { useProfile } from "@/lib/hooks/useProfile";
import { Lock } from "lucide-react";
import AdminBookingTable from "@/components/bookings/admin-booking-table";
import RagDashboard from "@/components/dashboard/rag-dashboard";
import UserRoleManagement from "@/components/dashboard/user-role-management";
import styles from "./page.module.scss";

type AdminTab = "bookings" | "rag" | "users";

export default function AdminPage() {
  const { user, hasPermission } = useAuth();
  const { profile } = useProfile(user?.id);
  const [activeTab, setActiveTab] = useState<AdminTab>("bookings");

  // Access control
  const canManageBookings = hasPermission("bookings.read_all");
  const canManageContent = hasPermission("rag.write");
  const canManageUsers = hasPermission("users.roles.manage");

  useEffect(() => {
    if (activeTab === "bookings" && !canManageBookings) {
      setActiveTab(canManageContent ? "rag" : "users");
    }
  }, [activeTab, canManageBookings, canManageContent]);

  if (!canManageBookings && !canManageContent && !canManageUsers) {
    return (
      <div className={styles.page}>
        <div className={styles.accessDenied}>
          <div className={styles.accessIcon}><Lock size={32} /></div>
          <span className={styles.accessText}>
            Access restricted to department administrators.
          </span>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <h1 className={styles.title}>Admin Dashboard</h1>
        <p className={styles.subtitle}>
          Manage booking approvals and the RAG knowledge base pipeline.
        </p>
      </div>

      <div className={styles.tabs}>
        <button
          className={`${styles.tab} ${
            activeTab === "bookings" ? styles.tabActive : ""
          }`}
          onClick={() => setActiveTab("bookings")}
          id="tab-bookings"
          hidden={!canManageBookings}
        >
          Booking Approvals
        </button>
        <button
          className={`${styles.tab} ${
            activeTab === "rag" ? styles.tabActive : ""
          }`}
          onClick={() => setActiveTab("rag")}
          id="tab-rag"
          hidden={!canManageContent}
        >
          RAG Pipeline
        </button>
        <button
          className={`${styles.tab} ${activeTab === "users" ? styles.tabActive : ""}`}
          onClick={() => setActiveTab("users")}
          id="tab-users"
          hidden={!canManageUsers}
        >
          User Roles
        </button>
      </div>

      <div className={styles.section}>
        {activeTab === "bookings" && canManageBookings ? (
          <AdminBookingTable userId={user!.id} />
        ) : activeTab === "rag" && canManageContent ? (
          <RagDashboard />
        ) : activeTab === "users" && canManageUsers ? (
          <UserRoleManagement />
        ) : null}
      </div>
    </div>
  );
}
