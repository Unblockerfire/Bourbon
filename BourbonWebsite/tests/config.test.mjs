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

test("download configuration is explicit and non-empty", () => {
  assert.match(
    config,
    /directDownloadUrl:\s*\n\s*"https:\/\/github\.com\/Unblockerfire\/Bourbon\/releases\/download\/v2\.0\.4\/Bourbon2\.0\.4\.dmg"/
  );
  assert.match(config, /minimumMacOSVersion: "14\.0"/);
});
