import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "Installing Windows apps",
  description: "Install Windows software into a Bourbon Bottle.",
  alternates: { canonical: "/docs/installing-windows-apps" }
};
export default function Page() {
  return <DocsPage slug="installing-windows-apps" />;
}
