import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import { SiteNav } from "@/components/SiteNav";
import { siteConfig } from "@/lib/siteConfig";
import "./globals.css";

export const viewport: Viewport = {
  themeColor: "#0b1220",
  colorScheme: "dark",
  width: "device-width",
  initialScale: 1
};

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.canonicalDomain),
  applicationName: siteConfig.productName,
  title: {
    default: `${siteConfig.productName} - Windows apps on macOS`,
    template: `%s - ${siteConfig.productName}`
  },
  description: siteConfig.tagline,
  alternates: {
    canonical: "/"
  },
  icons: {
    icon: [
      {
        url: "/assets/bourbon-app-icon.png?v=bourbon",
        sizes: "1024x1024",
        type: "image/png"
      }
    ],
    shortcut: [{ url: "/assets/bourbon-app-icon.png?v=bourbon" }],
    apple: [
      {
        url: "/assets/bourbon-app-icon.png?v=bourbon",
        sizes: "1024x1024",
        type: "image/png"
      }
    ]
  },
  manifest: "/manifest.webmanifest",
  openGraph: {
    type: "website",
    url: siteConfig.canonicalDomain,
    siteName: siteConfig.productName,
    title: `${siteConfig.productName} - Windows apps on macOS`,
    description: siteConfig.tagline,
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Bourbon for macOS"
      }
    ]
  },
  twitter: {
    card: "summary_large_image",
    title: `${siteConfig.productName} - Windows apps on macOS`,
    description: siteConfig.tagline,
    images: ["/og.png"]
  },
  robots: {
    index: true,
    follow: true
  }
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <a className="skipLink" href="#main">
          Skip to content
        </a>
        <SiteNav />
        {children}
      </body>
    </html>
  );
}
