"use client";

import { signOut } from "firebase/auth";
import {
  createGoogleAuth,
  type FirebaseBrowserConfig
} from "@/lib/firebase/client";

type AdminLogoutButtonProps = { firebaseConfig: FirebaseBrowserConfig | null };

export function AdminLogoutButton({ firebaseConfig }: AdminLogoutButtonProps) {
  async function logout() {
    await fetch("/api/admin/session", { method: "DELETE" });
    if (firebaseConfig) {
      try {
        const { auth } = createGoogleAuth(firebaseConfig);
        await signOut(auth);
      } catch {
        // The server session is already cleared; a browser SDK cleanup failure is non-blocking.
      }
    }
    window.location.assign("/admin/login");
  }

  return (
    <button className="button buttonSecondary" onClick={() => void logout()}>
      Logout
    </button>
  );
}
