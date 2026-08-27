import { createHash, timingSafeEqual } from "node:crypto";

export function tokenHash(token) {
  return createHash("sha256").update(token).digest("hex");
}

export function makeLicenseKey(licenseId, token) {
  return `${licenseId}.${token}`;
}

export function normalizeLicenseKey(value, licenseIdIsValid) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > 320) return null;
  const candidates = value.match(/BRBN-[A-Za-z0-9-]{8,64}\.[A-Za-z0-9_-]{64}/g) || [];
  const uniqueCandidates = [...new Set(candidates)];
  if (uniqueCandidates.length !== 1) return null;

  const key = uniqueCandidates[0];
  const separator = key.indexOf(".");
  const licenseId = key.slice(0, separator);
  const token = key.slice(separator + 1);
  return licenseIdIsValid(licenseId) && /^[A-Za-z0-9_-]{64}$/.test(token) ? key : null;
}

export function parseLicenseKey(value, licenseIdIsValid) {
  const key = normalizeLicenseKey(value, licenseIdIsValid);
  if (!key) return null;
  const separator = key.indexOf(".");
  if (separator < 1) return null;
  const licenseId = key.slice(0, separator);
  const token = key.slice(separator + 1);
  return licenseIdIsValid(licenseId) && /^[A-Za-z0-9_-]{64}$/.test(token)
    ? { licenseId, token }
    : null;
}

export function hashesMatch(left, right) {
  if (typeof left !== "string" || typeof right !== "string") return false;
  const leftBytes = Buffer.from(left, "hex");
  const rightBytes = Buffer.from(right, "hex");
  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}
