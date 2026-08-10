import type { Metadata } from "next";
import { DocsPage } from "@/components/DocsPage";
export const metadata: Metadata = {
  title: "Creating a Bottle",
  description: "Create an isolated Windows environment with Bourbon.",
  alternates: { canonical: "/docs/creating-a-bottle" }
};
export default function Page() {
  return <DocsPage slug="creating-a-bottle" />;
}
