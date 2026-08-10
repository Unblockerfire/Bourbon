import type { MetadataRoute } from "next";

import { siteConfig } from "@/lib/siteConfig";

const routes = [
  "",
  "/download",
  "/privacy",
  "/support",
  "/acknowledgments",
  "/docs",
  "/docs/getting-started",
  "/docs/installing-bourbon",
  "/docs/creating-a-bottle",
  "/docs/installing-windows-apps",
  "/docs/bourbonwine",
  "/docs/updates",
  "/docs/troubleshooting",
  "/docs/bug-reporting",
  "/docs/faq"
];

export default function sitemap(): MetadataRoute.Sitemap {
  return routes.map((route) => ({
    url: `${siteConfig.canonicalDomain}${route}`,
    lastModified: new Date(),
    changeFrequency: route === "" ? "weekly" : "monthly",
    priority: route === "" ? 1 : 0.7
  }));
}
