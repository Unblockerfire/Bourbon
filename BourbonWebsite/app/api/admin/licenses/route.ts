import { NextRequest, NextResponse } from "next/server";
import { requireBourbonAdmin } from "@/lib/adminAuth";

const runtimeUrl = "https://api.getbourbon.app/admin/licenses";

export async function POST(request: NextRequest) {
  await requireBourbonAdmin();
  const token = process.env.ADMIN_UPDATE_TOKEN;
  if (!token)
    return NextResponse.json(
      { error: "Runtime admin integration is not configured." },
      { status: 503 }
    );
  const body = (await request.json().catch(() => null)) as {
    operation?: string;
  } | null;
  if (!body || !["lookup", "moderate"].includes(body.operation || "")) {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }
  try {
    const { operation, ...payload } = body;
    const response = await fetch(
      `${runtimeUrl}/${operation === "lookup" ? "lookup" : "moderate"}`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${token}`
        },
        body: JSON.stringify(payload),
        cache: "no-store"
      }
    );
    const data = await response
      .json()
      .catch(() => ({ error: "Runtime API returned an invalid response." }));
    return NextResponse.json(data, { status: response.status });
  } catch {
    return NextResponse.json(
      { error: "Unable to reach the Runtime API." },
      { status: 502 }
    );
  }
}
