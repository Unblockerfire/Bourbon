import { NextResponse } from "next/server";

import { getLatestRelease } from "@/lib/download";

export const dynamic = "force-dynamic";

export async function GET() {
  const release = await getLatestRelease();

  return NextResponse.json(release, {
    headers: {
      "Cache-Control": "public, max-age=300, stale-while-revalidate=900"
    }
  });
}
