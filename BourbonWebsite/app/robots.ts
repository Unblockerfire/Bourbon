import type { MetadataRoute } from "next";

import { siteConfig } from "@/lib/siteConfig";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/"
    },
    sitemap: `${siteConfig.canonicalDomain}/sitemap.xml`,
    host: siteConfig.canonicalDomain
  };
}
