import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const config = readFileSync(
  new URL("../lib/siteConfig.ts", import.meta.url),
  "utf8"
);

test("public website config uses Bourbon production URLs", () => {
  const oldDomain = ["get", "wh", "isky", ".app"].join("");
  const oldSiteRepo = ["Wh", "isky", "Site"].join("");

  assert.match(config, /productName: "Bourbon"/);
  assert.match(config, /canonicalDomain: "https:\/\/getbourbon\.app"/);
  assert.equal(config.includes(oldDomain), false);
  assert.equal(config.includes(oldSiteRepo), false);
});

test("public app downloads are explicitly paused", () => {
  assert.match(config, /publicDownloadsPaused: true/);
  assert.match(config, /publicDownloadPauseMessage:/);
  assert.equal(config.includes("releases/download/"), false);
  assert.match(config, /minimumMacOSVersion: "14\.0"/);
});
