import { NextResponse } from "next/server";

const discordInviteUrl = "https://discord.gg/ACtsVCYvAS";

export function GET() {
  return NextResponse.redirect(discordInviteUrl, 308);
}
