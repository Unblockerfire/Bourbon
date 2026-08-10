import "server-only";

import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

function required(name: string) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

export function getFirebaseAdminAuth() {
  const app = getApps().length
    ? getApps()[0]
    : initializeApp({
        credential: cert({
          projectId: required("FIREBASE_ADMIN_PROJECT_ID"),
          clientEmail: required("FIREBASE_ADMIN_CLIENT_EMAIL"),
          privateKey: required("FIREBASE_ADMIN_PRIVATE_KEY").replace(
            /\\n/g,
            "\n"
          )
        })
      });
  return getAuth(app);
}
