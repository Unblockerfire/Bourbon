function warningText(value) {
  if (typeof value === "string") return value.trim();
  if (!value || typeof value !== "object") return "";
  for (const key of ["message", "reason", "text"]) {
    if (typeof value[key] === "string" && value[key].trim()) return value[key].trim();
  }
  return "";
}

export function licenseWarnings(data) {
  const candidates = [
    ...(Array.isArray(data.warnings) ? data.warnings : []),
    ...(Array.isArray(data.warningHistory) ? data.warningHistory : []),
    data.warning
  ];

  return [...new Set(candidates.map(warningText).filter(Boolean))].slice(0, 10);
}

export function evaluateLicense(data) {
  const status = typeof data?.status === "string" && data.status.trim() ? data.status.trim() : "unknown";
  const warnings = licenseWarnings(data || {});
  const allowed = status === "valid";
  const revoked = status === "revoked";

  return {
    status,
    allowed,
    isValid: allowed,
    revoked,
    warnings,
    reason: typeof data?.reason === "string" && data.reason.trim() ? data.reason.trim() : null
  };
}
