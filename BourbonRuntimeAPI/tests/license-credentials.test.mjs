import test from "node:test";
import assert from "node:assert/strict";
import { hashesMatch, makeLicenseKey, parseLicenseKey, tokenHash } from "../license-credentials.js";

const licenseId = "BRBN-ABCDEF1234567890";
const token = "a".repeat(64);
const isValidLicenseId = (value) => /^BRBN-[A-Za-z0-9-]{8,64}$/.test(value);

test("new license keys round-trip independently of archive names", () => {
  const key = makeLicenseKey(licenseId, token);
  assert.deepEqual(parseLicenseKey(key, isValidLicenseId), { licenseId, token });
  assert.equal(parseLicenseKey(licenseId + ".BourbonWine-1.0.1", isValidLicenseId), null);
});

test("malformed and short keys are rejected before lookup", () => {
  assert.equal(parseLicenseKey("not-a-license-key", isValidLicenseId), null);
  assert.equal(parseLicenseKey(licenseId + "." + "b".repeat(63), isValidLicenseId), null);
  assert.equal(parseLicenseKey(licenseId + "." + "b".repeat(64), isValidLicenseId)?.licenseId, licenseId);
});

test("credential hashes compare safely", () => {
  assert.equal(hashesMatch(tokenHash(token), tokenHash(token)), true);
  assert.equal(hashesMatch(tokenHash(token), tokenHash("b".repeat(64))), false);
});
