import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "Installing Bourbon",
  description: "Install Bourbon with GitHub Releases or Homebrew.",
  alternates: { canonical: "/docs/installing-bourbon" }
};
export default function Page() {
  return <DocsPage slug="installing-bourbon" />;
}
