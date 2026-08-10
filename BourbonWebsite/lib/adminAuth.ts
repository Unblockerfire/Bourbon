import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { getFirebaseAdminAuth } from "@/lib/firebase/admin";

export const SESSION_COOKIE = "bourbon_admin_session";
export const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 5;

export function isAuthorizedBourbonUid(uid: string) {
  return (
    Boolean(process.env.BOURBON_ADMIN_FIREBASE_UID) &&
    uid === process.env.BOURBON_ADMIN_FIREBASE_UID
  );
}

export async function requireBourbonAdmin() {
  const session = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!session) redirect("/admin/login");
  try {
    const token = await getFirebaseAdminAuth().verifySessionCookie(
      session,
      true
    );
    if (!isAuthorizedBourbonUid(token.uid)) redirect("/admin/login");
    return token;
  } catch {
    redirect("/admin/login");
  }
}
