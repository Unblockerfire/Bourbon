"use client";

import { Download, ExternalLink } from "lucide-react";
import { useEffect, useState } from "react";

import { siteConfig } from "@/lib/siteConfig";

type DownloadState = {
  version: string | null;
  downloadUrl: string;
  releaseUrl: string;
  source: "github" | "fallback";
};

export function DownloadButton({ compact = false }: { compact?: boolean }) {
  const [release, setRelease] = useState<DownloadState>({
    version: siteConfig.currentVersion,
    downloadUrl: siteConfig.directDownloadUrl || siteConfig.releasesPageUrl,
    releaseUrl: siteConfig.releasesPageUrl,
    source: "fallback"
  });

  useEffect(() => {
    let ignore = false;

    fetch("/api/latest-release")
      .then((response) => (response.ok ? response.json() : null))
      .then((data: DownloadState | null) => {
        if (!ignore && data?.downloadUrl) {
          setRelease(data);
        }
      })
      .catch(() => {
        // The configured fallback remains active when GitHub is unavailable.
      });

    return () => {
      ignore = true;
    };
  }, []);

  return (
    <a
      className={compact ? "button buttonCompact" : "button buttonPrimary"}
      href={release.downloadUrl}
      aria-label={`Download ${siteConfig.productName}${
        release.version ? ` ${release.version}` : ""
      } for macOS`}
    >
      <Download aria-hidden="true" size={compact ? 17 : 20} />
      <span>{compact ? "Download" : "Download for macOS"}</span>
      {!compact && release.version ? <small>v{release.version}</small> : null}
    </a>
  );
}

export function ReleasesLink() {
  return (
    <a className="button buttonSecondary" href={siteConfig.releasesPageUrl}>
      <ExternalLink aria-hidden="true" size={18} />
      <span>View releases</span>
    </a>
  );
}
