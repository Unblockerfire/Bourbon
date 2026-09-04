import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const websiteRoot = new URL("../", import.meta.url);
const source = (path) => readFileSync(new URL(path, websiteRoot), "utf8");

test("website surfaces download pause states instead of public DMG links", () => {
  const buttons = source("components/DownloadButton.tsx");
  const downloadPage = source("app/download/page.tsx");
  const latestReleaseRoute = source("app/api/latest-release/route.ts");

  assert.equal(buttons.includes("href="), false);
  assert.match(buttons, /Downloads paused/);
  assert.match(buttons, /Development downloads paused/);
  assert.match(downloadPage, /Public downloads are paused/);
  assert.equal(downloadPage.includes("releasesPageUrl"), false);
  assert.match(latestReleaseRoute, /status: 503/);
  assert.match(latestReleaseRoute, /Cache-Control.*no-store/);
});
