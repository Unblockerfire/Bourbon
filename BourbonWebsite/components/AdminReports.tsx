"use client";

import { useEffect, useState } from "react";

type Report = {
  reportId?: string;
  receivedAt?: string;
  appName?: string;
  appVersion?: string;
  buildNumber?: string;
  issueType?: string;
};

type ReportsResponse = { ok: boolean; reports?: Report[]; error?: string };

export function AdminReports() {
  const [state, setState] = useState<{
    reports: Report[];
    error: string | null;
  } | null>(null);

  useEffect(() => {
    fetch("/api/admin/reports", { cache: "no-store" })
      .then(async (response) => {
        const data = (await response.json()) as ReportsResponse;
        if (!response.ok || !data.ok) {
          throw new Error(data.error || "Unable to load reports.");
        }
        setState({ reports: data.reports || [], error: null });
      })
      .catch(() =>
        setState({ reports: [], error: "Reports are unavailable right now." })
      );
  }, []);

  if (!state) return <p className="adminEmptyState">Loading report intake…</p>;
  if (state.error) {
    return (
      <p className="formError" role="alert">
        {state.error}
      </p>
    );
  }
  if (state.reports.length === 0) {
    return <p className="adminEmptyState">No reports have been received.</p>;
  }

  return (
    <div className="adminReportTable" role="table" aria-label="Problem reports">
      <div className="adminReportHeader" role="row">
        <span role="columnheader">Report</span>
        <span role="columnheader">App</span>
        <span role="columnheader">Category</span>
        <span role="columnheader">Received</span>
      </div>
      {state.reports
        .slice()
        .reverse()
        .map((report, index) => (
          <div
            className="adminReportRow"
            key={report.reportId || index}
            role="row"
          >
            <strong role="cell">{report.reportId || "Bug report"}</strong>
            <span role="cell">
              {report.appName || "Unspecified app"}
              <small>
                {report.appVersion || report.buildNumber || "Unknown version"}
              </small>
            </span>
            <span role="cell">{report.issueType || "No category"}</span>
            <time role="cell" dateTime={report.receivedAt}>
              {report.receivedAt
                ? new Date(report.receivedAt).toLocaleString()
                : "Unknown"}
            </time>
          </div>
        ))}
    </div>
  );
}
