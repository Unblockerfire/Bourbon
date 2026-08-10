import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "Troubleshooting",
  description: "Troubleshoot Bourbon setup, runtime, app, and update issues.",
  alternates: { canonical: "/docs/troubleshooting" }
};
export default function Page() {
  return <DocsPage slug="troubleshooting" />;
}
