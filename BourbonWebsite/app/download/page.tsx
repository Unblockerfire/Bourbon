import type { Metadata } from "next";
import {
  MonitorDown,
  ShieldCheck
} from "lucide-react";

import {
  DevelopmentDownloadButton,
  DownloadButton,
  ReleasesLink
} from "@/components/DownloadButton";
import { siteConfig } from "@/lib/siteConfig";

export const metadata: Metadata = {
  title: "Downloads",
  description: `Public ${siteConfig.productName} downloads are temporarily paused.`,
  alternates: {
    canonical: "/download"
  }
};

export default function DownloadPage() {
  return (
    <main id="main" className="pageShell">
      <section className="pageHero">
        <p className="eyebrow">Downloads</p>
        <h1>Public downloads are paused.</h1>
        <p>
          {siteConfig.publicDownloadPauseMessage} Existing installations are
          unaffected. Private tester builds are distributed separately.
        </p>
        <div className="buttonRow">
          <DownloadButton />
          <DevelopmentDownloadButton />
          <ReleasesLink />
        </div>
      </section>

      <section className="infoGrid" aria-label="Download details">
        <article>
          <MonitorDown aria-hidden="true" size={26} />
          <h2>Current configured version</h2>
          <p>{siteConfig.currentVersion}</p>
        </article>
        <article>
          <ShieldCheck aria-hidden="true" size={26} />
          <h2>Minimum macOS</h2>
          <p>{siteConfig.minimumMacOSVersion} or later on Apple Silicon.</p>
        </article>
      </section>
    </main>
  );
}
