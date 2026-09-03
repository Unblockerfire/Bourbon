import { siteConfig } from "./siteConfig";

export type LatestRelease = {
  paused: true;
  message: string;
};

export async function getLatestRelease(): Promise<LatestRelease> {
  return {
    paused: true,
    message: siteConfig.downloadsPauseMessage
  };
}
