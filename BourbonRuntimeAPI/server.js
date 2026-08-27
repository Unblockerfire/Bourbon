import express from "express";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomBytes, randomUUID } from "node:crypto";
import { FieldValue, licenseStore } from "./firebase-admin.js";
import { evaluateLicense } from "./license-policy.js";
import { hashesMatch, makeLicenseKey, parseLicenseKey, tokenHash } from "./license-credentials.js";

const app = express();
app.use(express.json({ limit: "256kb" }));

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const updateConfigPath = path.join(__dirname, "updates.json");
const reportsPath = process.env.REPORTS_PATH || path.join(__dirname, "reports.json");
const updateChannels = JSON.parse(fs.readFileSync(updateConfigPath, "utf8"));

const requiredEnv = [
  "R2_ACCOUNT_ID",
  "R2_ACCESS_KEY_ID",
  "R2_SECRET_ACCESS_KEY",
  "R2_BUCKET"
];

for (const key of requiredEnv) {
  if (!process.env[key]) {
    console.error(`Missing required env var: ${key}`);
    process.exit(1);
  }
}

const s3 = new S3Client({
  region: "auto",
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY
  }
});

async function signedUrl(key) {
  const command = new GetObjectCommand({
    Bucket: process.env.R2_BUCKET,
    Key: key
  });

  return getSignedUrl(s3, command, { expiresIn: 300 });
}

app.get("/health", (_, res) => {
  res.json({ ok: true, service: "bourbon-runtime-api" });
});

app.get("/runtime/latest", async (_, res) => {
  const archiveName = "BourbonWine-1.0.0-macOS-x86_64.tar.gz";

  res.json({
    version: "1.0.1",
    wineVersion: "wine-11.11-199-ge3bb4552d76",
    archiveName,
    sha256: "3c3e5cec14e47058b90932f08a1650dacb4ccd15129c4dd6785321e4ab456bd1",
    plistUrl: await signedUrl("BourbonWineVersion.plist"),
    archiveUrl: await signedUrl(archiveName),
    expiresInSeconds: 300
  });
});

function escapeXml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function formatRssDate(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? new Date().toUTCString() : date.toUTCString();
}

function appcastForChannel(channel, release) {
  const title = channel === "pre" ? "Bourbon Pre-release Updates" : "Bourbon Stable Updates";
  const signatureAttribute = release.edSignature
    ? ` sparkle:edSignature="${escapeXml(release.edSignature)}"`
    : "";

  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
  xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
  xmlns:bourbon="https://getbourbon.app/appcast"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${escapeXml(title)}</title>
    <link>https://github.com/Unblockerfire/Bourbon/releases</link>
    <description>${escapeXml(title)}</description>
    <item>
      <title>Bourbon ${escapeXml(release.version)}</title>
      <pubDate>${escapeXml(formatRssDate(release.pubDate))}</pubDate>
      <sparkle:version>${escapeXml(release.build)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXml(release.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escapeXml(release.minimumSystemVersion)}</sparkle:minimumSystemVersion>
      ${release.minimumAutoupdateVersion
        ? `<sparkle:minimumAutoupdateVersion>${escapeXml(release.minimumAutoupdateVersion)}</sparkle:minimumAutoupdateVersion>`
        : ""}
      <enclosure
        url="${escapeXml(release.dmgUrl)}"
        length="${escapeXml(release.dmgLength)}"
        type="application/x-apple-diskimage"${signatureAttribute} />
      ${release.releaseType ? `<bourbon:releaseType>${escapeXml(release.releaseType)}</bourbon:releaseType>` : ""}
    </item>
  </channel>
</rss>
`;
}

function sendAppcast(res, channel) {
  const release = updateChannels[channel];

  if (!release) {
    res.status(404).json({ ok: false, error: "Unknown update channel" });
    return;
  }

  res.type("application/xml").send(appcastForChannel(channel, release));
}

app.get("/updates/stable/appcast.xml", (_, res) => {
  sendAppcast(res, "stable");
});

app.get("/updates/pre/appcast.xml", (_, res) => {
  sendAppcast(res, "pre");
});

function isValidPublishBody(body) {
  return body &&
    ["stable", "pre"].includes(body.channel) &&
    typeof body.version === "string" &&
    typeof body.build === "string" &&
    typeof body.dmgUrl === "string" &&
    body.dmgUrl.startsWith("https://github.com/Unblockerfire/Bourbon/releases/download/") &&
    Number.isInteger(body.dmgLength) &&
    body.dmgLength > 0 &&
    typeof body.pubDate === "string" &&
    typeof body.minimumSystemVersion === "string" &&
    (body.minimumAutoupdateVersion === null ||
      body.minimumAutoupdateVersion === undefined ||
      typeof body.minimumAutoupdateVersion === "string") &&
    (body.releaseType === null || body.releaseType === undefined || typeof body.releaseType === "string") &&
    (body.edSignature === null || body.edSignature === undefined || typeof body.edSignature === "string");
}

function adminAuthorized(req) {
  const adminToken = process.env.ADMIN_UPDATE_TOKEN;
  return Boolean(adminToken) && req.header("authorization") === `Bearer ${adminToken}`;
}

function licenseIdIsValid(value) {
  return typeof value === "string" && /^BRBN-[A-Za-z0-9-]{8,64}$/.test(value);
}

function stringValue(value, maximum = 500) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= maximum
    ? value.trim()
    : null;
}

const recoveryAttempts = new Map();
function requestRateLimited(req, limit, windowMs = 60_000) {
  const now = Date.now();
  const address = req.ip || req.socket.remoteAddress || "unknown";
  const recent = (recoveryAttempts.get(address) || []).filter((timestamp) => now - timestamp < windowMs);
  recent.push(now);
  recoveryAttempts.set(address, recent);
  if (recoveryAttempts.size > 10_000) {
    for (const [key, timestamps] of recoveryAttempts) {
      if (timestamps.at(-1) < now - windowMs) recoveryAttempts.delete(key);
    }
  }
  return recent.length > limit;
}

function toIso(value) {
  return value?.toDate instanceof Function ? value.toDate().toISOString() : null;
}

function licenseSummary(id, data) {
  return {
    licenseId: id,
    status: data.status || "unknown",
    reason: data.reason || null,
    appealAllowed: Boolean(data.appealAllowed),
    deletionScheduledAt: toIso(data.deletionScheduledAt),
    lastValidationAt: toIso(data.lastValidationAt),
    macosVersion: data.macosVersion || "unknown",
    appVersion: data.appVersion || "unknown",
    architecture: data.architecture || "unknown",
    updatedAt: toIso(data.updatedAt)
  };
}

function licenseBackend(res) {
  try {
    return licenseStore();
  } catch (error) {
    console.error("License Firestore initialization failed", { name: error?.name, code: error?.code, message: error?.message });
    res.status(503).json({ ok: false, error: "License service is unavailable" });
    return null;
  }
}

function adminOnly(req, res) {
  if (!adminAuthorized(req)) {
    res.status(401).json({ ok: false, error: "Unauthorized" });
    return false;
  }
  return true;
}

app.post("/licenses/activate", async (req, res) => {
  const displayName = stringValue(req.body?.displayName, 120);
  const appVersion = stringValue(req.body?.appVersion, 120);
  const macosVersion = stringValue(req.body?.macosVersion, 160);
  const architecture = stringValue(req.body?.architecture, 16);
  const installId = stringValue(req.body?.installId, 160);
  if (!displayName || !appVersion || !macosVersion || !installId || !["arm64", "x86_64"].includes(architecture)) {
    res.status(400).json({ ok: false, error: "Invalid license activation request" });
    return;
  }
  const db = licenseBackend(res);
  if (!db) return;
  const licenseId = `BRBN-${randomUUID().replaceAll("-", "").slice(0, 16).toUpperCase()}`;
  const licenseToken = randomBytes(48).toString("base64url");
  await db.collection("licenses").doc(licenseId).set({
    status: "valid",
    reason: null,
    appealAllowed: false,
    deletionScheduledAt: null,
    tokenHash: tokenHash(licenseToken),
    credentialVersion: 2,
    displayName,
    installId,
    appVersion,
    macosVersion,
    architecture,
    lastValidationAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp()
  });
  res.status(201).json({ publicLicenseId: licenseId, licenseToken, licenseKey: makeLicenseKey(licenseId, licenseToken), displayName, status: "Free", messages: [], permissions: ["distillery", "local-installs"] });
});

app.post("/license/recover", async (req, res) => {
  if (requestRateLimited(req, 12)) {
    res.status(429).json({ ok: false, error: "Too many license recovery attempts" });
    return;
  }
  const parsed = parseLicenseKey(req.body?.licenseKey, licenseIdIsValid);
  if (!parsed) {
    res.status(400).json({ ok: false, error: "Invalid license key" });
    return;
  }
  const db = licenseBackend(res);
  if (!db) return;
  const reference = db.collection("licenses").doc(parsed.licenseId);
  const snapshot = await reference.get();
  if (!snapshot.exists || !hashesMatch(snapshot.data().tokenHash, tokenHash(parsed.token))) {
    res.status(401).json({ ok: false, error: "Invalid license key" });
    return;
  }
  const data = snapshot.data();
  if (data.credentialVersion !== 2) {
    res.status(401).json({ ok: false, error: "Invalid license key" });
    return;
  }
  const decision = evaluateLicense(data);
  const response = {
    licenseId: parsed.licenseId,
    ...decision,
    appealAllowed: Boolean(data.appealAllowed),
    deletionScheduledAt: toIso(data.deletionScheduledAt),
    checkedAt: new Date().toISOString()
  };
  if (!decision.allowed) {
    res.status(403).json(response);
    return;
  }
  await reference.update({ lastValidationAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  res.json({
    ...response,
    publicLicenseId: parsed.licenseId,
    licenseToken: parsed.token,
    licenseKey: makeLicenseKey(parsed.licenseId, parsed.token),
    displayName: data.displayName || "Bourbon User",
    status: data.status,
    messages: [],
    permissions: ["distillery", "local-installs"]
  });
});
app.post("/license/validate", async (req, res) => {
  if (requestRateLimited(req, 30)) {
    res.status(429).json({ ok: false, error: "Too many license validation attempts" });
    return;
  }
  const licenseId = req.body?.licenseId;
  const licenseToken = req.body?.licenseToken;
  if (!licenseIdIsValid(licenseId) || !stringValue(licenseToken, 256)) {
    res.status(400).json({ ok: false, error: "Invalid license validation request" });
    return;
  }
  const db = licenseBackend(res);
  if (!db) return;
  const reference = db.collection("licenses").doc(licenseId);
  const snapshot = await reference.get();
  if (!snapshot.exists || !hashesMatch(snapshot.data().tokenHash, tokenHash(licenseToken))) {
    res.status(401).json({ ok: false, error: "Invalid license" });
    return;
  }
  const data = snapshot.data();
  await reference.update({ lastValidationAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  const decision = evaluateLicense(data);
  res.json({ licenseId, ...decision, appealAllowed: Boolean(data.appealAllowed), deletionScheduledAt: toIso(data.deletionScheduledAt), checkedAt: new Date().toISOString() });
});

app.post("/license/appeal", async (req, res) => {
  const licenseId = req.body?.licenseId;
  const licenseToken = req.body?.licenseToken;
  if (!licenseIdIsValid(licenseId) || !stringValue(licenseToken, 256)) {
    res.status(400).json({ ok: false, error: "Invalid license appeal request" });
    return;
  }
  const db = licenseBackend(res);
  if (!db) return;
  const reference = db.collection("licenses").doc(licenseId);
  const snapshot = await reference.get();
  if (!snapshot.exists || !hashesMatch(snapshot.data().tokenHash, tokenHash(licenseToken))) {
    res.status(401).json({ ok: false, error: "Invalid license" });
    return;
  }
  await reference.collection("appeals").add({ status: stringValue(req.body?.status, 40) || "unknown", reason: stringValue(req.body?.reason, 1000), submittedAt: FieldValue.serverTimestamp() });
  res.json({ ok: true });
});

app.post("/admin/licenses/lookup", async (req, res) => {
  if (!adminOnly(req, res)) return;
  const licenseId = req.body?.licenseId;
  if (!licenseIdIsValid(licenseId)) {
    res.status(400).json({ ok: false, error: "Invalid license ID" });
    return;
  }
  const db = licenseBackend(res);
  if (!db) return;
  const snapshot = await db.collection("licenses").doc(licenseId).get();
  if (!snapshot.exists) {
    res.status(404).json({ ok: false, error: "License not found" });
    return;
  }
  res.json({ ok: true, license: licenseSummary(snapshot.id, snapshot.data()) });
});

app.post("/admin/licenses/moderate", async (req, res) => {
  if (!adminOnly(req, res)) return;
  const licenseId = req.body?.licenseId;
  const action = req.body?.action;
  const reason = stringValue(req.body?.reason, 1000);
  if (!licenseIdIsValid(licenseId) || !["pause", "delete"].includes(action) || !reason || typeof req.body?.appealAllowed !== "boolean") {
    res.status(400).json({ ok: false, error: "Invalid moderation request" });
    return;
  }
  const db = licenseBackend(res);
  if (!db) return;
  const reference = db.collection("licenses").doc(licenseId);
  const snapshot = await reference.get();
  if (!snapshot.exists) {
    res.status(404).json({ ok: false, error: "License not found" });
    return;
  }
  const deletionScheduledAt = action === "delete" && !req.body.appealAllowed ? new Date(Date.now() + 72 * 60 * 60 * 1000) : null;
  const status = action === "pause" ? "paused" : "scheduledForDeletion";
  await reference.update({ status, reason, appealAllowed: req.body.appealAllowed, deletionScheduledAt, updatedAt: FieldValue.serverTimestamp() });
  await reference.collection("audit").add({ action, reason, appealAllowed: req.body.appealAllowed, deletionScheduledAt, actor: "website-admin", createdAt: FieldValue.serverTimestamp() });
  const updated = await reference.get();
  res.json({ ok: true, license: licenseSummary(updated.id, updated.data()) });
});
app.post("/admin/updates/publish", (req, res) => {
  if (!process.env.ADMIN_UPDATE_TOKEN) {
    res.status(501).json({
      ok: false,
      error: "Admin update publishing is not configured"
    });
    return;
  }

  if (!adminAuthorized(req)) {
    res.status(401).json({ ok: false, error: "Unauthorized" });
    return;
  }

  if (!isValidPublishBody(req.body)) {
    res.status(400).json({ ok: false, error: "Invalid update payload" });
    return;
  }

  updateChannels[req.body.channel] = {
    version: req.body.version,
    build: req.body.build,
    dmgUrl: req.body.dmgUrl,
    dmgLength: req.body.dmgLength,
    pubDate: req.body.pubDate,
    minimumSystemVersion: req.body.minimumSystemVersion,
    minimumAutoupdateVersion: req.body.minimumAutoupdateVersion ?? null,
    releaseType: req.body.releaseType ?? null,
    edSignature: req.body.edSignature ?? null
  };

  res.json({
    ok: true,
    channel: req.body.channel,
    version: req.body.version,
    build: req.body.build
  });
});

function readReports() {
  try {
    return JSON.parse(fs.readFileSync(reportsPath, "utf8"));
  } catch {
    return [];
  }
}

function writeReports(reports) {
  fs.mkdirSync(path.dirname(reportsPath), { recursive: true });
  fs.writeFileSync(reportsPath, JSON.stringify(reports, null, 2));
}

function reportIdForIndex(index) {
  return `BR-${String(index).padStart(6, "0")}`;
}

function redact(value) {
  if (typeof value !== "string") {
    return value;
  }

  return value
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[redacted-email]")
    .replace(
      /(token|api[_-]?key|secret|password|licenseToken|privateLicenseToken)["'\s:=]+[A-Za-z0-9._\-+/=]{8,}/gi,
      "$1=[redacted]"
    )
    .replace(/BRBN-[A-Za-z0-9-]{12,}/g, "[redacted-license-token]");
}

function sanitizeObject(value) {
  if (Array.isArray(value)) {
    return value.map(sanitizeObject);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, sanitizeObject(entry)])
    );
  }

  return redact(value);
}

function isStringOrNull(value) {
  return value === null || value === undefined || typeof value === "string";
}

function isValidReportBody(body) {
  return body &&
    typeof body.reportType === "string" &&
    typeof body.title === "string" &&
    typeof body.description === "string" &&
    typeof body.stepsToReproduce === "string" &&
    typeof body.expectedBehavior === "string" &&
    typeof body.actualBehavior === "string" &&
    isStringOrNull(body.contactEmail) &&
    (body.diagnostics === undefined || typeof body.diagnostics === "object") &&
    isStringOrNull(body.logs) &&
    typeof body.appVersion === "string" &&
    typeof body.buildNumber === "string" &&
    isStringOrNull(body.licenseId) &&
    typeof body.timestamp === "string";
}

app.post("/reports/bug", (req, res) => {
  if (!isValidReportBody(req.body)) {
    res.status(400).json({ ok: false, error: "Invalid report payload" });
    return;
  }

  const reports = readReports();
  const reportId = reportIdForIndex(reports.length + 1);
  const report = {
    reportId,
    receivedAt: new Date().toISOString(),
    ...sanitizeObject(req.body),
    contactEmail: req.body.contactEmail || null
  };

  reports.push(report);
  writeReports(reports);

  res.json({ ok: true, reportId });
});

app.get("/admin/reports", (req, res) => {
  if (!adminAuthorized(req)) {
    res.status(401).json({ ok: false, error: "Unauthorized" });
    return;
  }

  res.json({ ok: true, reports: readReports() });
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Bourbon runtime API listening on ${port}`);
});
