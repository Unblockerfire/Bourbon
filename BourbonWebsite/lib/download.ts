import { siteConfig } from "./siteConfig";

export type LatestRelease = {
  available: false;
  version: null;
  downloadUrl: null;
  releaseUrl: null;
  source: "paused";
  message: string;
};

export async function getLatestRelease(): Promise<LatestRelease> {
  return {
    available: false,
    version: null,
    downloadUrl: null,
    releaseUrl: null,
    source: "paused",
    message: siteConfig.publicDownloadPauseMessage
  };
}
