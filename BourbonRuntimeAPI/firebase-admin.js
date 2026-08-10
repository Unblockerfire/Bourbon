import { cert, getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

export function licenseStore() {
  const app = getApps().length
    ? getApps()[0]
    : initializeApp({
        credential: cert({
          projectId: required("FIREBASE_ADMIN_PROJECT_ID"),
          clientEmail: required("FIREBASE_ADMIN_CLIENT_EMAIL"),
          privateKey: required("FIREBASE_ADMIN_PRIVATE_KEY").replace(/\\n/g, "\n")
        })
      });
  return getFirestore(app);
}

export { FieldValue };