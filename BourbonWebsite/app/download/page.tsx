import type { Metadata } from "next";
import { MonitorDown, ShieldCheck } from "lucide-react";

import { DownloadButton } from "@/components/DownloadButton";
import { siteConfig } from "@/lib/siteConfig";

export const metadata: Metadata = {
  title: "Downloads",
  description: `${siteConfig.productName} downloads are temporarily paused while a runtime update is validated.`,
  alternates: {
    canonical: "/download"
  }
};

export default function DownloadPage() {
  return (
    <main id="main" className="pageShell">
      <section className="pageHero">
        <p className="eyebrow">Downloads</p>
        <h1>Downloads temporarily paused.</h1>
        <p>{siteConfig.downloadsPauseMessage}</p>
        <p>
          Please avoid installing the current public build while this work is in
          progress.
        </p>
        <div className="buttonRow">
          <DownloadButton />
        </div>
      </section>

      <section className="infoGrid" aria-label="Download details">
        <article>
          <MonitorDown aria-hidden="true" size={26} />
          <h2>Current status</h2>
          <p>Public downloads are unavailable during validation.</p>
        </article>
        <article>
          <ShieldCheck aria-hidden="true" size={26} />
          <h2>Minimum macOS</h2>
          <p>{siteConfig.minimumMacOSVersion} or later on Apple Silicon.</p>
        </article>
        <article>
          <h2>Availability</h2>
          <p>A corrected public build is expected by the end of the week.</p>
        </article>
      </section>
    </main>
  );
}
