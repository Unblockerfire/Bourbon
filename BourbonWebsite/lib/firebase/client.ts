import { getApp, getApps, initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider } from "firebase/auth";

export type FirebaseBrowserConfig = {
  apiKey: string;
  authDomain: string;
  projectId: string;
  appId: string;
};

export function createGoogleAuth(config: FirebaseBrowserConfig) {
  const app = getApps().length ? getApp() : initializeApp(config);
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: "select_account" });
  return { auth: getAuth(app), provider };
}
