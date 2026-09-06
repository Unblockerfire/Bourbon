import Image from "next/image";
import Link from "next/link";
import {
  Apple,
  ArrowDown,
  BadgeCheck,
  Box,
  ChevronRight,
  Cpu,
  FolderOpen,
  Gauge,
  MonitorDown,
  ShieldCheck,
  Sparkles
} from "lucide-react";

import {
  DevelopmentDownloadButton,
  DownloadButton,
  ReleasesLink
} from "@/components/DownloadButton";
import { featureCards, siteConfig } from "@/lib/siteConfig";

const facts = [
  { value: `v${siteConfig.currentVersion}`, label: "Latest release" },
  { value: `macOS ${siteConfig.minimumMacOSVersion}+`, label: "System" },
  { value: "Universal 2", label: "Architecture" },
  { value: "Free", label: "Price" }
];

const capabilities = [
  {
    icon: Box,
    title: "One app, one bottle",
    description:
      "Keep every Windows app in a separate, managed environment with its own settings, files, registry, and dependencies."
  },
  {
    icon: MonitorDown,
    title: "Install without the terminal",
    description:
      "Choose an installer and let Bourbon guide setup with familiar Mac controls and clear progress."
  },
  {
    icon: Gauge,
    title: "Runtime care included",
    description:
      "Bourbon keeps its compatibility runtime organized and delivers signed updates through Sparkle."
  },
  {
    icon: ShieldCheck,
    title: "Diagnostics with boundaries",
    description:
      "Built-in reports redact sensitive tokens and contact details before diagnostic information is stored."
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
    <main id="main" className="homePage">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />

      <section className="heroSection">
        <div className="heroCopy heroEntrance">
          <div className="releasePill">
            <BadgeCheck aria-hidden="true" size={16} />
            <span>Bourbon {siteConfig.currentVersion} is available</span>
            <ChevronRight aria-hidden="true" size={15} />
          </div>
          <p className="eyebrow">A native home for Windows apps</p>
          <h1>
            Windows apps.
            <span>At home on your Mac.</span>
          </h1>
          <p className="heroLead">
            Bourbon makes Wine feel like part of macOS—create an isolated
            bottle, choose an installer, and get back to the app you wanted to
            run.
          </p>
          <div className="buttonRow">
            <DownloadButton />
            <DevelopmentDownloadButton />
            <ReleasesLink />
          </div>
          <p className="heroFinePrint">
            <Apple aria-hidden="true" size={15} />
            Apple Silicon + Intel · Requires macOS{" "}
            {siteConfig.minimumMacOSVersion}+
          </p>
        </div>

        <div
          className="heroProduct heroEntrance"
          aria-label="Bourbon app preview"
        >
          <div className="heroAura" aria-hidden="true" />
          <div className="macWindow">
            <div className="windowBar" aria-hidden="true">
              <span />
              <span />
              <span />
              <p>Bourbon</p>
            </div>
            <Image
              src="/assets/bourbon-create-bottle.png"
              alt="Bourbon Create Bottle screen"
              width={1478}
              height={1628}
              priority
            />
          </div>
          <div className="floatingNote floatingNoteTop">
            <Sparkles aria-hidden="true" size={17} />
            <span>Native SwiftUI</span>
          </div>
          <div className="floatingNote floatingNoteBottom">
            <BadgeCheck aria-hidden="true" size={17} />
            <span>Ready to create</span>
          </div>
        </div>

        <a
          className="scrollCue"
          href="#experience"
          aria-label="Explore Bourbon"
        >
          <ArrowDown aria-hidden="true" size={17} />
        </a>
      </section>

      <section
        className="factRail"
        aria-label="Bourbon release facts"
        data-reveal
      >
        <dl>
          {facts.map((fact) => (
            <div key={fact.label}>
              <dt>{fact.label}</dt>
              <dd>{fact.value}</dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="statementBand" id="experience" data-reveal>
        <p className="eyebrow">Made to feel familiar</p>
        <h2>
          The compatibility layer stays behind the scenes.
          <span>You stay in control.</span>
        </h2>
        <p className="statementLead">
          No sprawling setup ritual or mystery folders. Bourbon wraps the Wine
          pieces you need in an interface that speaks Mac.
        </p>
      </section>

      <section className="featureShowcase" aria-label="Bourbon features">
        {featureCards.map((card, index) => (
          <article className="featureStory" key={card.title} data-reveal>
            <div className="featureStoryCopy">
              <span className="featureNumber">0{index + 1}</span>
              <p className="eyebrow">
                {index === 0
                  ? "Start clean"
                  : index === 1
                    ? "Stay organized"
                    : "Launch with confidence"}
              </p>
              <h2>{card.title}</h2>
              <p>{card.description}</p>
              <Link className="textLink" href="/docs/getting-started">
                Learn how it works
                <ChevronRight aria-hidden="true" size={17} />
              </Link>
            </div>
            <div className="featureStoryMedia">
              <Image
                src={card.image}
                alt={card.alt}
                width={1478}
                height={1628}
              />
            </div>
          </article>
        ))}
      </section>

      <section
        className="capabilityBand"
        aria-labelledby="capability-title"
        data-reveal
      >
        <div className="capabilityIntro">
          <p className="eyebrow">Thoughtful by default</p>
          <h2 id="capability-title">
            Power when you need it. Calm when you don&apos;t.
          </h2>
          <p>
            The technical work is still there. Bourbon simply puts it in the
            right place, with the right amount of explanation.
          </p>
        </div>
        <div className="capabilityGrid">
          {capabilities.map((item) => (
            <article key={item.title} className="capabilityItem">
              <div className="capabilityIcon">
                <item.icon aria-hidden="true" size={22} />
              </div>
              <h3>{item.title}</h3>
              <p>{item.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section
        className="downloadPanel"
        aria-labelledby="download-title"
        data-reveal
      >
        <div className="downloadIcon" aria-hidden="true">
          <Image
            src="/assets/bourbon-app-icon-20260809.png"
            alt=""
            width={96}
            height={96}
          />
        </div>
        <div>
          <p className="eyebrow">Your next pour</p>
          <h2 id="download-title">Bring your Windows apps home.</h2>
          <p>
            Download Bourbon {siteConfig.currentVersion} for an Apple Silicon
            or Intel Mac running macOS {siteConfig.minimumMacOSVersion} or later.
          </p>
        </div>
        <div className="buttonRow">
          <DownloadButton />
          <Link className="button buttonSecondary" href="/download">
            <FolderOpen aria-hidden="true" size={18} />
            <span>More options</span>
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
          <Link href="/docs">Documentation</Link>
          <Link href="/support">Support</Link>
          <Link href="/privacy">Privacy</Link>
        </nav>
        <p>
          <Cpu aria-hidden="true" size={15} />
          Universal 2 for Apple Silicon + Intel
        </p>
      </footer>
    </main>
  );
}
