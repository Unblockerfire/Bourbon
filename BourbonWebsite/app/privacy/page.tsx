import type { Metadata } from "next";
import { Database, FileWarning, ShieldCheck } from "lucide-react";

import { siteConfig } from "@/lib/siteConfig";

export const metadata: Metadata = {
  title: "Privacy",
  description: `${siteConfig.productName} privacy information for the website, downloads, updates, and bug reports.`,
  alternates: {
    canonical: "/privacy"
  }
};

export default function PrivacyPage() {
  return (
    <main id="main" className="pageShell">
      <section className="pageHero">
        <p className="eyebrow">Privacy</p>
        <h1>Plain-language privacy for Bourbon.</h1>
        <p>
          This website is a public product site. The Bourbon runtime API
          supports app updates, runtime downloads, and optional bug reports
          submitted from the app.
        </p>
      </section>

      <section className="infoGrid">
        <article>
          <ShieldCheck aria-hidden="true" size={26} />
          <h2>Website visits</h2>
          <p>
            The website does not require an account, payment details, or a
            contact form. Standard hosting logs may be processed by
            infrastructure providers to operate and secure the service.
          </p>
        </article>
        <article>
          <Database aria-hidden="true" size={26} />
          <h2>Downloads and updates</h2>
          <p>
            Download buttons may request public GitHub release metadata. Bourbon
            app update checks use the configured appcast endpoint under
            api.getbourbon.app.
          </p>
        </article>
        <article>
          <FileWarning aria-hidden="true" size={26} />
          <h2>Bug reports</h2>
          <p>
            Bourbon report intake validates report fields and redacts email
            addresses, tokens, API keys, secrets, passwords, and Bourbon license
            tokens from submitted diagnostics before storage.
          </p>
        </article>
      </section>
    </main>
  );
}
