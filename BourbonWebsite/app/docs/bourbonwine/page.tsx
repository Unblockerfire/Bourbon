import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "BourbonWine",
  description: "Learn how Bourbon manages its Windows runtime.",
  alternates: { canonical: "/docs/bourbonwine" }
};
export default function Page() {
  return <DocsPage slug="bourbonwine" />;
}
