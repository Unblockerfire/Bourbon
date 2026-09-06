import type { Metadata } from "next";
import {
  ExternalLink,
  Github,
  MonitorDown,
  ShieldCheck,
  Terminal
} from "lucide-react";

import {
  DevelopmentDownloadButton,
  DownloadButton,
  ReleasesLink
} from "@/components/DownloadButton";
import { siteConfig } from "@/lib/siteConfig";

export const metadata: Metadata = {
  title: "Downloads",
  description: `Download ${siteConfig.productName} for macOS and review release options.`,
  alternates: {
    canonical: "/download"
  }
};

export default function DownloadPage() {
  return (
    <main id="main" className="pageShell">
      <section className="pageHero">
        <p className="eyebrow">Downloads</p>
        <h1>Get Bourbon for macOS.</h1>
        <p>
          The primary download uses the configured Bourbon release destination.
          When GitHub latest-release API is available, the button resolves to
          the newest DMG asset; otherwise it falls back to the configured
          release.
        </p>
        <p>
          Bourbon 2.0.8 restores the production license connection and is
          available through Bourbon&apos;s normal in-app updater.
        </p>
        <p>
          The Development DMG is a diagnostic test build and does not replace
          the current stable release.
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
          <p>{siteConfig.minimumMacOSVersion} or later on Apple Silicon or Intel.</p>
        </article>
        <article>
          <Github aria-hidden="true" size={26} />
          <h2>Release archive</h2>
          <p>
            <a href={siteConfig.releasesPageUrl}>
              GitHub releases <ExternalLink aria-hidden="true" size={14} />
            </a>
          </p>
        </article>
        <article>
          <Terminal aria-hidden="true" size={26} />
          <h2>Homebrew</h2>
          <p>
            <code>brew install --cask Unblockerfire/Bourbon/bourbon</code>
          </p>
        </article>
      </section>
    </main>
  );
}
