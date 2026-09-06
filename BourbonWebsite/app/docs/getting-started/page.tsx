import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "Getting started",
  description: "Set up Bourbon on an Apple Silicon or Intel Mac.",
  alternates: { canonical: "/docs/getting-started" }
};
export default function Page() {
  return <DocsPage slug="getting-started" />;
}
