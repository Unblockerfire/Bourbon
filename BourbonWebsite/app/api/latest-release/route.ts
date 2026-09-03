import { NextResponse } from "next/server";

import { getLatestRelease } from "@/lib/download";

export const dynamic = "force-dynamic";

export async function GET() {
  const release = await getLatestRelease();

  return NextResponse.json(release, {
    status: 503,
    headers: {
      "Cache-Control": "no-store"
    }
  });
}
