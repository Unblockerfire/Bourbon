"use client";

import { Download, ExternalLink } from "lucide-react";

import { siteConfig } from "@/lib/siteConfig";

export function DownloadButton({ compact = false }: { compact?: boolean }) {
  return (
    <button
      className={`${compact ? "button buttonCompact" : "button buttonPrimary"} buttonDisabled`}
      disabled
      title={siteConfig.downloadsPauseMessage}
    >
      <Download aria-hidden="true" size={compact ? 17 : 20} />
      <span>{compact ? "Paused" : "Downloads paused"}</span>
    </button>
  );
}

export function ReleasesLink() {
  return (
    <span
      className="button buttonSecondary buttonDisabled"
      aria-disabled="true"
    >
      <ExternalLink aria-hidden="true" size={18} />
      <span>Release archive paused</span>
    </span>
  );
}
