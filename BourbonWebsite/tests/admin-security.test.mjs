import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

function source(path) {
  return readFileSync(new URL(path, import.meta.url), "utf8");
}

const auth = source("../lib/adminAuth.ts");
const sessionRoute = source("../app/api/admin/session/route.ts");
const adminPage = source("../app/admin/page.tsx");
const trigger = source("../components/HiddenAdminFaqItem.tsx");

test("only the configured Firebase UID is authorized", () => {
  assert.match(auth, /uid === process\.env\.BOURBON_ADMIN_FIREBASE_UID/);
  assert.match(auth, /Boolean\(process\.env\.BOURBON_ADMIN_FIREBASE_UID\)/);
});

test("admin sessions are verified, including revocation", () => {
  assert.match(auth, /verifySessionCookie\(\s*session,\s*true\s*\)/);
  assert.match(auth, /if \(!session\) redirect\("\/admin\/login"\)/);
  assert.match(auth, /catch \{\s*redirect\("\/admin\/login"\)/);
});

test("session exchange verifies ID tokens and sets a secure server cookie", () => {
  assert.match(sessionRoute, /verifyIdToken\(idToken\)/);
  assert.match(sessionRoute, /createSessionCookie\(idToken/);
  assert.match(sessionRoute, /httpOnly: true/);
  assert.match(sessionRoute, /sameSite: "lax"/);
  assert.match(sessionRoute, /secure: process\.env\.NODE_ENV === "production"/);
  assert.match(sessionRoute, /isAuthorizedBourbonUid\(decoded\.uid\)/);
});

test("the protected page requires a verified server session before rendering", () => {
  assert.match(adminPage, /await requireBourbonAdmin\(\)/);
});

test("the FAQ sequence requires five clicks inside a two-second window", () => {
  assert.match(trigger, /REQUIRED_CLICKS = 5/);
  assert.match(trigger, /CLICK_WINDOW_MS = 2_000/);
  assert.match(trigger, /router\.push\("\/admin\/login"\)/);
});
