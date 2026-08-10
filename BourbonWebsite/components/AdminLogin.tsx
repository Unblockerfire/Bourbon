"use client";

import Link from "next/link";
import { useState } from "react";
import { signInWithPopup, signOut } from "firebase/auth";
import {
  createGoogleAuth,
  type FirebaseBrowserConfig
} from "@/lib/firebase/client";

type AdminLoginProps = { firebaseConfig: FirebaseBrowserConfig | null };

export function AdminLogin({ firebaseConfig }: AdminLoginProps) {
  const [error, setError] = useState<string | null>(null);
  const [isSigningIn, setIsSigningIn] = useState(false);

  async function signIn() {
    if (!firebaseConfig) {
      setError("Administration sign-in is not configured.");
      return;
    }

    setError(null);
    setIsSigningIn(true);
    const { auth, provider } = createGoogleAuth(firebaseConfig);
    try {
      const result = await signInWithPopup(auth, provider);
      const idToken = await result.user.getIdToken();
      const response = await fetch("/api/admin/session", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ idToken })
      });

      if (!response.ok) {
        await signOut(auth);
        setError(
          response.status === 403
            ? "This account is not authorized."
            : "Unable to sign in. Try again."
        );
        return;
      }

      window.location.assign("/admin");
    } catch {
      setError("Unable to sign in. Try again.");
    } finally {
      setIsSigningIn(false);
    }
  }

  return (
    <main id="main" className="pageShell">
      <section className="pageHero adminLogin">
        <p className="eyebrow">Secure access</p>
        <h1>Bourbon Administration</h1>
        <p>Use the authorized Google account to continue.</p>
        <div className="buttonRow">
          <Link className="button buttonSecondary" href="/docs/faq">
            ← Back
          </Link>
          <button
            className="button buttonPrimary"
            disabled={isSigningIn}
            onClick={() => void signIn()}
          >
            {isSigningIn ? "Signing in…" : "Continue with Google"}
          </button>
        </div>
        {error ? (
          <p className="formError" role="alert">
            {error}
          </p>
        ) : null}
      </section>
    </main>
  );
}
