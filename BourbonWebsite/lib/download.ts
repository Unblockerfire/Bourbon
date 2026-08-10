import { siteConfig } from "./siteConfig";

export type LatestRelease = {
  version: string | null;
  downloadUrl: string;
  releaseUrl: string;
  source: "github" | "fallback";
};

type GitHubAsset = {
  name?: string;
  browser_download_url?: string;
};

type GitHubRelease = {
  tag_name?: string;
  html_url?: string;
  assets?: GitHubAsset[];
};

export async function getLatestRelease(): Promise<LatestRelease> {
  const fallback = {
    version: siteConfig.currentVersion,
    downloadUrl: siteConfig.directDownloadUrl || siteConfig.releasesPageUrl,
    releaseUrl: siteConfig.releasesPageUrl,
    source: "fallback" as const
  };

  try {
    const response = await fetch(
      `https://api.github.com/repos/${siteConfig.githubRepository}/releases/latest`,
      {
        headers: {
          Accept: "application/vnd.github+json",
          "User-Agent": "getbourbon.app"
        },
        next: { revalidate: 900 }
      }
    );

    if (!response.ok) {
      return fallback;
    }

    const release = (await response.json()) as GitHubRelease;
    const dmgAsset = release.assets?.find((asset) =>
      asset.name?.toLowerCase().endsWith(".dmg")
    );

    return {
      version: release.tag_name?.replace(/^v/i, "") || fallback.version,
      downloadUrl:
        dmgAsset?.browser_download_url ||
        release.html_url ||
        fallback.downloadUrl,
      releaseUrl: release.html_url || fallback.releaseUrl,
      source: "github"
    };
  } catch {
    return fallback;
  }
}
