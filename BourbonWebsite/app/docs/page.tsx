import type { Metadata } from "next";

import { DocsPage } from "@/components/DocsPage";

export const metadata: Metadata = {
  title: "Documentation",
  description: "First-party documentation for Bourbon on macOS.",
  alternates: { canonical: "/docs" }
};

export default function DocsHomePage() {
  return <DocsPage slug="home" />;
}
