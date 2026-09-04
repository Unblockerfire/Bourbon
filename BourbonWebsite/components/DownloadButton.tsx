"use client";

import { PauseCircle } from "lucide-react";

import { siteConfig } from "@/lib/siteConfig";

export function DownloadButton({ compact = false }: { compact?: boolean }) {
  return (
    <span
      className={compact ? "button buttonCompact" : "button buttonPrimary"}
      aria-disabled="true"
      aria-label={`${siteConfig.productName} downloads are temporarily paused`}
      role="status"
    >
      <PauseCircle aria-hidden="true" size={compact ? 17 : 20} />
      <span>{compact ? "Paused" : "Downloads paused"}</span>
    </span>
  );
}

export function ReleasesLink() {
  return (
    <span className="button buttonSecondary" aria-disabled="true" role="status">
      <PauseCircle aria-hidden="true" size={18} />
      <span>Release downloads paused</span>
    </span>
  );
}

export function DevelopmentDownloadButton() {
  return (
    <span
      className="button buttonSecondary"
      aria-disabled="true"
      aria-label={`Development ${siteConfig.productName} downloads are temporarily paused`}
      role="status"
    >
      <PauseCircle aria-hidden="true" size={18} />
      <span>Development downloads paused</span>
    </span>
  );
}
