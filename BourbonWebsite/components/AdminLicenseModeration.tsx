"use client";

import { useState } from "react";

type License = {
  licenseId: string;
  status: string;
  reason: string | null;
  appealAllowed: boolean;
  deletionScheduledAt: string | null;
  lastValidationAt: string | null;
  macosVersion: string;
  appVersion: string;
  architecture: string;
};

export function AdminLicenseModeration() {
  const [licenseId, setLicenseId] = useState("");
  const [license, setLicense] = useState<License | null>(null);
  const [action, setAction] = useState("");
  const [appealAllowed, setAppealAllowed] = useState("");
  const [reason, setReason] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function request(payload: Record<string, unknown>) {
    const response = await fetch("/api/admin/licenses", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload)
    });
    const data = (await response.json()) as {
      license?: License;
      error?: string;
    };
    if (!response.ok) throw new Error(data.error || "Request failed.");
    return data;
  }
  async function lookup() {
    setBusy(true);
    setMessage(null);
    try {
      const data = await request({
        operation: "lookup",
        licenseId: licenseId.trim()
      });
      setLicense(data.license || null);
    } catch (error) {
      setLicense(null);
      setMessage(
        error instanceof Error ? error.message : "Could not load that license."
      );
    } finally {
      setBusy(false);
    }
  }
  async function moderate() {
    if (!license || !action || !reason.trim() || appealAllowed === "") return;
    if (!window.confirm(`Apply ${action} to ${license.licenseId}?`)) return;
    setBusy(true);
    setMessage(null);
    try {
      const data = await request({
        operation: "moderate",
        licenseId: license.licenseId,
        action,
        reason: reason.trim(),
        appealAllowed: appealAllowed === "yes"
      });
      setLicense(data.license || null);
      setMessage("Action applied.");
    } catch (error) {
      setMessage(
        error instanceof Error ? error.message : "Could not apply that action."
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <section
        className="adminPanel"
        aria-labelledby="license-moderation-heading"
      >
        <div className="adminPanelHeading">
          <div>
            <h2 id="license-moderation-heading">Find License</h2>
            <p>Search a Bourbon license to review its current status.</p>
          </div>
        </div>
        <div className="adminLookupRow">
          <input
            aria-label="License ID"
            value={licenseId}
            onChange={(event) => setLicenseId(event.target.value)}
            placeholder="BRBN-00000001"
            disabled={busy}
          />
          <button
            onClick={() => void lookup()}
            disabled={busy || !licenseId.trim()}
          >
            {busy ? "Searching…" : "Search"}
          </button>
        </div>
        {message ? (
          <p className="formError" role="alert">
            {message}
          </p>
        ) : null}
      </section>
      {license ? (
        <section className="adminPanel adminLicenseSummary">
          <div className="adminPanelHeading">
            <div>
              <h2>License</h2>
              <p>{license.licenseId}</p>
            </div>
            <span className="adminLiveBadge">{license.status}</span>
          </div>
          <dl>
            <div>
              <dt>macOS version</dt>
              <dd>{license.macosVersion}</dd>
            </div>
            <div>
              <dt>App version</dt>
              <dd>{license.appVersion}</dd>
            </div>
            <div>
              <dt>Last validation</dt>
              <dd>
                {license.lastValidationAt
                  ? new Date(license.lastValidationAt).toLocaleString()
                  : "Never"}
              </dd>
            </div>
            <div>
              <dt>Architecture</dt>
              <dd>{license.architecture}</dd>
            </div>
          </dl>
          {license.reason ? (
            <p className="adminNotice">Reason: {license.reason}</p>
          ) : null}
        </section>
      ) : null}
      <section
        className="adminPanel adminActionPanel"
        aria-labelledby="action-heading"
      >
        <div className="adminPanelHeading">
          <div>
            <h2 id="action-heading">Action</h2>
            <p>Select a license, action, reason, and appeal availability.</p>
          </div>
        </div>
        <div className="adminControlGrid">
          <label>
            Action
            <select
              value={action}
              disabled={!license || busy}
              onChange={(event) => setAction(event.target.value)}
            >
              <option value="">Select action</option>
              <option value="pause">Pause license</option>
              <option value="delete">Delete license</option>
            </select>
          </label>
          <label>
            Appeal
            <select
              value={appealAllowed}
              disabled={!license || busy}
              onChange={(event) => setAppealAllowed(event.target.value)}
            >
              <option value="">Select option</option>
              <option value="yes">Yes, appeal allowed</option>
              <option value="no">No, appeal not allowed</option>
            </select>
          </label>
          <label className="adminReasonField">
            Reason
            <textarea
              value={reason}
              disabled={!license || busy}
              onChange={(event) => setReason(event.target.value)}
              placeholder="Reason required"
              rows={3}
            />
          </label>
        </div>
        <div className="adminPanelFooter">
          <span>
            {license
              ? "Actions are audited."
              : "Find a license to unlock controls."}
          </span>
          <button
            onClick={() => void moderate()}
            disabled={
              !license ||
              busy ||
              !action ||
              !reason.trim() ||
              appealAllowed === ""
            }
          >
            {busy ? "Applying…" : "Apply Action"}
          </button>
        </div>
      </section>
    </>
  );
}
