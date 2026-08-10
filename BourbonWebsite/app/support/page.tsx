import type { Metadata } from "next";
import Link from "next/link";
import { Bug, ExternalLink, Github, LifeBuoy } from "lucide-react";

import { siteConfig } from "@/lib/siteConfig";

export const metadata: Metadata = {
  title: "Support",
  description: `Support resources for ${siteConfig.productName} on macOS.`,
  alternates: {
    canonical: "/support"
  }
};

export default function SupportPage() {
  return (
    <main id="main" className="pageShell">
      <section className="pageHero">
        <p className="eyebrow">Support</p>
        <h1>Help for Bourbon users.</h1>
        <p>
          Start with the release notes and documentation, then use the built-in
          report flow when an installer or bottle needs closer attention.
        </p>
      </section>

      <section className="infoGrid">
        <article>
          <Github aria-hidden="true" size={26} />
          <h2>GitHub</h2>
          <p>
            <a href={siteConfig.githubRepositoryUrl}>
              Open the Bourbon repository{" "}
              <ExternalLink aria-hidden="true" size={14} />
            </a>
          </p>
        </article>
        <article>
          <LifeBuoy aria-hidden="true" size={26} />
          <h2>Documentation</h2>
          <p>
            <Link href={siteConfig.documentationUrl}>
              Read Bourbon documentation{" "}
              <ExternalLink aria-hidden="true" size={14} />
            </Link>
          </p>
        </article>
        <article>
          <Bug aria-hidden="true" size={26} />
          <h2>Reports</h2>
          <p>
            In the macOS app, use the built-in report option for recent crashes,
            installer issues, and diagnostics that should be redacted before
            storage.
          </p>
        </article>
      </section>
    </main>
  );
}
