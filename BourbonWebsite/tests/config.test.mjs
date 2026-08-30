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
  const version = config.match(/currentVersion: "([^"]+)"/)?.[1];
  const downloadVersion = config.match(
    /directDownloadUrl:\s*\n\s*"https:\/\/github\.com\/Unblockerfire\/Bourbon\/releases\/download\/v([^/]+)\/Bourbon([^/]+)\.dmg"/
  );

  assert.ok(version, "currentVersion must be configured");
  assert.ok(downloadVersion, "directDownloadUrl must point to a Bourbon DMG");
  assert.equal(downloadVersion[1], version);
  assert.equal(downloadVersion[2], version);
  assert.match(
    config,
    /developmentDownloadUrl:\s*\n\s*"https:\/\/github\.com\/Unblockerfire\/Bourbon\/releases\/download\/development-97639d8f\/Bourbon-diagnostic-97639d8f0777\.dmg"/
  );
  assert.match(config, /minimumMacOSVersion: "14\.0"/);
});
