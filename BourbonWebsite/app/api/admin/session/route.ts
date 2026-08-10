import { NextRequest, NextResponse } from "next/server";
import {
  SESSION_COOKIE,
  SESSION_MAX_AGE_SECONDS,
  isAuthorizedBourbonUid
} from "@/lib/adminAuth";
import { getFirebaseAdminAuth } from "@/lib/firebase/admin";

const cookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/",
  maxAge: SESSION_MAX_AGE_SECONDS
};

export async function POST(request: NextRequest) {
  const { idToken } = await request.json().catch(() => ({}));
  if (typeof idToken !== "string")
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const auth = getFirebaseAdminAuth();
    const decoded = await auth.verifyIdToken(idToken);
    if (!isAuthorizedBourbonUid(decoded.uid))
      return NextResponse.json(
        { error: "This account is not authorized." },
        { status: 403 }
      );
    const session = await auth.createSessionCookie(idToken, {
      expiresIn: SESSION_MAX_AGE_SECONDS * 1000
    });
    const response = NextResponse.json({ ok: true });
    response.cookies.set(SESSION_COOKIE, session, cookieOptions);
    return response;
  } catch {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
}

export async function DELETE(request: NextRequest) {
  const session = request.cookies.get(SESSION_COOKIE)?.value;
  if (session) {
    try {
      const token = await getFirebaseAdminAuth().verifySessionCookie(session);
      await getFirebaseAdminAuth().revokeRefreshTokens(token.uid);
    } catch {}
  }
  const response = NextResponse.json({ ok: true });
  response.cookies.set(SESSION_COOKIE, "", { ...cookieOptions, maxAge: 0 });
  return response;
}
