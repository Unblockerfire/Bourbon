import type { Metadata } from "next";
import { AdminLogin } from "@/components/AdminLogin";
import type { FirebaseBrowserConfig } from "@/lib/firebase/client";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Bourbon Administration",
  robots: { index: false, follow: false }
};

function firebaseConfig(): FirebaseBrowserConfig | null {
  const {
    NEXT_PUBLIC_FIREBASE_API_KEY: apiKey,
    NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN: authDomain,
    NEXT_PUBLIC_FIREBASE_PROJECT_ID: projectId,
    NEXT_PUBLIC_FIREBASE_APP_ID: appId
  } = process.env;
  return apiKey && authDomain && projectId && appId
    ? { apiKey, authDomain, projectId, appId }
    : null;
}

export default function Page() {
  return <AdminLogin firebaseConfig={firebaseConfig()} />;
}
