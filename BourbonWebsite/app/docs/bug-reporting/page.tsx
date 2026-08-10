import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "Bug reporting",
  description: "Send a privacy-conscious Bourbon problem report.",
  alternates: { canonical: "/docs/bug-reporting" }
};
export default function Page() {
  return <DocsPage slug="bug-reporting" />;
}
