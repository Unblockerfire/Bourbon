import Image from "next/image";
import Link from "next/link";
import {
  Apple,
  BadgeCheck,
  Box,
  Bug,
  ChevronRight,
  Cpu,
  Folder,
  Gauge,
  MonitorDown,
  TerminalSquare
} from "lucide-react";

import { DownloadButton, ReleasesLink } from "@/components/DownloadButton";
import { featureCards, siteConfig } from "@/lib/siteConfig";

const facts = [
  `${siteConfig.productName} ${siteConfig.currentVersion}`,
  `macOS ${siteConfig.minimumMacOSVersion}+`,
  "Apple Silicon",
  "Native SwiftUI app"
];

const capabilities = [
  {
    icon: Box,
    title: "Bottles keep apps tidy",
    description:
      "Each Windows app can live in its own managed environment with separate settings, files, registry data, and dependencies."
  },
  {
    icon: MonitorDown,
    title: "Drop in installers",
    description:
      "Bourbon accepts common Windows installer formats and guides setup with macOS controls instead of terminal-first steps."
  },
  {
    icon: Gauge,
    title: "Runtime updates are handled",
    description:
      "Sparkle appcasts and BourbonWine runtime metadata keep the app and compatibility stack moving together."
  },
  {
    icon: Bug,
    title: "Reports with less noise",
    description:
      "The built-in report flow redacts sensitive tokens and contact details before storing diagnostic reports."
  }
];

export default function HomePage() {
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: siteConfig.productName,
    operatingSystem: `macOS ${siteConfig.minimumMacOSVersion} or later`,
    applicationCategory: "UtilitiesApplication",
    url: siteConfig.canonicalDomain,
    downloadUrl: siteConfig.directDownloadUrl,
    softwareVersion: siteConfig.currentVersion,
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD"
    }
  };

  return (
    <main id="main">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />
      <section className="heroSection">
        <div className="heroCopy">
          <Image
            className="heroIcon"
            src="/assets/bourbon-app-icon-20260809.png"
            alt=""
            width={132}
            height={132}
            priority
          />
          <p className="eyebrow">Bourbon for macOS</p>
          <h1>
            Windows apps, poured into a{" "}
            <span className="gradientText">native Mac home.</span>
          </h1>
          <p className="heroLead">
            Bourbon gives Apple Silicon Macs a polished way to create bottles,
            install Windows apps, manage runtimes, and keep compatibility work
            approachable.
          </p>
          <div className="buttonRow">
            <DownloadButton />
            <ReleasesLink />
          </div>
          <dl className="factPills" aria-label="Bourbon release facts">
            {facts.map((fact) => (
              <div key={fact}>
                <dt className="srOnly">Fact</dt>
                <dd>{fact}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      <section className="statementBand" aria-labelledby="statement-title">
        <p className="eyebrow">Built for the Mac you already use</p>
        <h2 id="statement-title">
          No sprawling setup ritual. No mystery folders. A careful macOS wrapper
          around the Wine pieces Bourbon needs.
        </h2>
      </section>

      <section className="featureGrid" aria-label="Bourbon feature previews">
        {featureCards.map((card, index) => (
          <article
            className={`featureCard featureCard${index + 1}`}
            key={card.title}
          >
            <div className="featureImage">
              <Image
                src={card.image}
                alt={card.alt}
                width={1478}
                height={1628}
              />
            </div>
            <div>
              <h2>{card.title}</h2>
              <p>{card.description}</p>
            </div>
          </article>
        ))}
      </section>
      <section className="capabilityBand" aria-labelledby="capability-title">
        <div>
          <p className="eyebrow">Bourbon in practice</p>
          <h2 id="capability-title">
            A focused toolkit for running Windows software.
          </h2>
        </div>
        <div className="capabilityGrid">
          {capabilities.map((item) => (
            <article key={item.title} className="capabilityItem">
              <item.icon aria-hidden="true" size={24} />
              <h3>{item.title}</h3>
              <p>{item.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="downloadPanel" aria-labelledby="download-title">
        <div>
          <p className="eyebrow">Ready when you are</p>
          <h2 id="download-title">Download Bourbon for macOS.</h2>
          <p>
            Requires an Apple Silicon Mac running macOS{" "}
            {siteConfig.minimumMacOSVersion} or later.
          </p>
        </div>
        <div className="buttonRow">
          <DownloadButton />
          <Link className="button buttonSecondary" href="/download">
            <ChevronRight aria-hidden="true" size={18} />
            <span>Download options</span>
          </Link>
        </div>
      </section>

      <footer className="siteFooter">
        <div>
          <Image
            src="/assets/bourbon-app-icon-20260809.png"
            alt=""
            width={36}
            height={36}
          />
          <span>{siteConfig.productName}</span>
        </div>
        <nav aria-label="Footer navigation">
          <Link href="/download">Downloads</Link>
          <Link href="/support">Support</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/acknowledgments">Acknowledgments</Link>
        </nav>
        <p>
          <Apple aria-hidden="true" size={16} />
          <Cpu aria-hidden="true" size={16} />
          <Folder aria-hidden="true" size={16} />
          <TerminalSquare aria-hidden="true" size={16} />
          <BadgeCheck aria-hidden="true" size={16} />
        </p>
      </footer>
    </main>
  );
}
