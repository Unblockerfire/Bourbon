import test from "node:test";
import assert from "node:assert/strict";
import { evaluateLicense, licenseWarnings } from "../license-policy.js";

test("active valid license proceeds without a warning", () => {
  assert.deepEqual(evaluateLicense({ status: "valid" }), {
    status: "valid",
    allowed: true,
    isValid: true,
    revoked: false,
    warnings: [],
    reason: null
  });
});

test("active license warning is returned without blocking", () => {
  assert.deepEqual(evaluateLicense({ status: "valid", warning: "Please review your account notice." }), {
    status: "valid",
    allowed: true,
    isValid: true,
    revoked: false,
    warnings: ["Please review your account notice."],
    reason: null
  });
});

test("active warnings are reduced to safe warning text", () => {
  assert.deepEqual(licenseWarnings({
    warningHistory: [
      { message: "First warning", internalOnly: "do not expose" },
      { reason: "Second warning" },
      { text: "First warning" }
    ]
  }), ["First warning", "Second warning"]);
});

test("revoked license is blocked with its backend reason", () => {
  assert.deepEqual(evaluateLicense({ status: "revoked", reason: "Revoked by support review." }), {
    status: "revoked",
    allowed: false,
    isValid: false,
    revoked: true,
    warnings: [],
    reason: "Revoked by support review."
  });
});

test("other blocked and unknown states cannot proceed", () => {
  for (const status of ["paused", "deleted", "banned", "expired", "scheduledForDeletion", "unknown"]) {
    assert.equal(evaluateLicense({ status }).allowed, false);
    assert.equal(evaluateLicense({ status }).isValid, false);
  }
});
test("unknown license data cannot proceed", () => {
  assert.equal(evaluateLicense({}).allowed, false);
  assert.equal(evaluateLicense({ status: "not-a-supported-state" }).isValid, false);
});
