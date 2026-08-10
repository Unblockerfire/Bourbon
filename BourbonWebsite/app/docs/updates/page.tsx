import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "Updates",
  description: "Keep Bourbon up to date with Sparkle or Homebrew.",
  alternates: { canonical: "/docs/updates" }
};
export default function Page() {
  return <DocsPage slug="updates" />;
}
