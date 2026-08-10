import { NextResponse } from "next/server";
import { requireBourbonAdmin } from "@/lib/adminAuth";

type RuntimeReport = {
  reportId?: unknown;
  receivedAt?: unknown;
  appName?: unknown;
  appVersion?: unknown;
  buildNumber?: unknown;
  issueType?: unknown;
};

function optionalString(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

export async function GET() {
  await requireBourbonAdmin();
  const token = process.env.ADMIN_UPDATE_TOKEN;
  if (!token) {
    return NextResponse.json(
      { error: "Runtime admin integration is not configured." },
      { status: 503 }
    );
  }

  try {
    const response = await fetch("https://api.getbourbon.app/admin/reports", {
      headers: { authorization: `Bearer ${token}` },
      cache: "no-store"
    });
    if (!response.ok) {
      return NextResponse.json(
        { error: "Unable to load reports." },
        { status: response.status }
      );
    }

    const payload = (await response.json()) as { reports?: RuntimeReport[] };
    const reports = Array.isArray(payload.reports)
      ? payload.reports.map((report) => ({
          reportId: optionalString(report.reportId),
          receivedAt: optionalString(report.receivedAt),
          appName: optionalString(report.appName),
          appVersion: optionalString(report.appVersion),
          buildNumber: optionalString(report.buildNumber),
          issueType: optionalString(report.issueType)
        }))
      : [];
    return NextResponse.json({ ok: true, reports });
  } catch {
    return NextResponse.json(
      { error: "Unable to load reports." },
      { status: 502 }
    );
  }
}
