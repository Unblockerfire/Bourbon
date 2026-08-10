import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "FAQ",
  description: "Frequently asked questions about Bourbon.",
  alternates: { canonical: "/docs/faq" }
};
export default function Page() {
  return <DocsPage slug="faq" />;
}
