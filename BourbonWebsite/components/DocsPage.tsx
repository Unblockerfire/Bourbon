import type { ReactNode } from "react";
import Image from "next/image";
import Link from "next/link";
import { ArrowRight, ExternalLink, Info, TriangleAlert } from "lucide-react";

import { siteConfig } from "@/lib/siteConfig";
import { HiddenAdminFaqItem } from "@/components/HiddenAdminFaqItem";

type DocSlug =
  | "home"
  | "getting-started"
  | "installing-bourbon"
  | "creating-a-bottle"
  | "installing-windows-apps"
  | "bourbonwine"
  | "updates"
  | "troubleshooting"
  | "bug-reporting"
  | "faq";

const navigation: Array<{ href: string; label: string }> = [
  { href: "/docs", label: "Documentation home" },
  { href: "/docs/getting-started", label: "Getting started" },
  { href: "/docs/installing-bourbon", label: "Installing Bourbon" },
  { href: "/docs/creating-a-bottle", label: "Creating a Bottle" },
  { href: "/docs/installing-windows-apps", label: "Installing Windows apps" },
  { href: "/docs/bourbonwine", label: "BourbonWine" },
  { href: "/docs/updates", label: "Updates" },
  { href: "/docs/troubleshooting", label: "Troubleshooting" },
  { href: "/docs/bug-reporting", label: "Bug reporting" },
  { href: "/docs/faq", label: "FAQ" }
];

const titles: Record<DocSlug, string> = {
  home: "Bourbon documentation",
  "getting-started": "Getting started",
  "installing-bourbon": "Installing Bourbon",
  "creating-a-bottle": "Creating a Bottle",
  "installing-windows-apps": "Installing Windows apps",
  bourbonwine: "BourbonWine",
  updates: "Updates",
  troubleshooting: "Troubleshooting",
  "bug-reporting": "Bug reporting",
  faq: "Frequently asked questions"
};

function Callout({
  children,
  warning = false
}: {
  children: ReactNode;
  warning?: boolean;
}) {
  const Icon = warning ? TriangleAlert : Info;
  return (
    <aside className={`docsCallout${warning ? " docsCalloutWarning" : ""}`}>
      <Icon aria-hidden="true" size={21} />
      <div>{children}</div>
    </aside>
  );
}

function DocLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link className="docsTextLink" href={href}>
      {children} <ArrowRight aria-hidden="true" size={16} />
    </Link>
  );
}

function DocsLayout({
  slug,
  children
}: {
  slug: DocSlug;
  children: ReactNode;
}) {
  const activeHref = slug === "home" ? "/docs" : `/docs/${slug}`;
  return (
    <main id="main" className="docsShell">
      <aside className="docsSidebar" aria-label="Documentation navigation">
        <p className="eyebrow">Bourbon Docs</p>
        <nav>
          {navigation.map((item) => (
            <Link
              aria-current={item.href === activeHref ? "page" : undefined}
              className={item.href === activeHref ? "active" : undefined}
              href={item.href}
              key={item.href}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </aside>
      <details className="docsMobileNav">
        <summary>Docs menu: {titles[slug]}</summary>
        <nav aria-label="Documentation navigation">
          {navigation.map((item) => (
            <Link
              aria-current={item.href === activeHref ? "page" : undefined}
              href={item.href}
              key={item.href}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </details>
      <article className="docsArticle">{children}</article>
    </main>
  );
}

function DocsHome() {
  return (
    <DocsLayout slug="home">
      <p className="eyebrow">First-party help</p>
      <h1>Everything you need to pour your first Bottle.</h1>
      <p className="docsLead">
        Bourbon Docs explains the supported setup, installation, runtime,
        update, and support flows for Bourbon on macOS. It is kept alongside the
        product so it reflects what the current app can do.
      </p>
      <div className="docsCardGrid">
        <section>
          <h2>Set up Bourbon</h2>
          <p>
            Check your Mac, install the app, and learn what happens on first
            launch.
          </p>
          <DocLink href="/docs/getting-started">Start here</DocLink>
        </section>
        <section>
          <h2>Make a Bottle</h2>
          <p>
            Create an isolated Windows environment, then choose an installer.
          </p>
          <DocLink href="/docs/creating-a-bottle">Create a Bottle</DocLink>
        </section>
        <section>
          <h2>Keep going</h2>
          <p>
            Learn about BourbonWine, updates, troubleshooting, and reporting
            issues.
          </p>
          <DocLink href="/docs/troubleshooting">Get help</DocLink>
        </section>
      </div>
      <section className="docsSection">
        <h2>Documentation map</h2>
        <ul className="docsLinkList">
          {navigation.slice(1).map((item) => (
            <li key={item.href}>
              <DocLink href={item.href}>{item.label}</DocLink>
            </li>
          ))}
        </ul>
      </section>
    </DocsLayout>
  );
}

function GettingStarted() {
  return (
    <DocsLayout slug="getting-started">
      <p className="eyebrow">Getting started</p>
      <h1>Windows software, in a native Mac workflow.</h1>
      <p className="docsLead">
        Bourbon is a native macOS app for creating Bottles, installing Windows
        software, and launching it through the runtime Bourbon manages.
      </p>
      <section className="docsSection">
        <h2>What you need</h2>
        <ul>
          <li>An Apple Silicon Mac with an M-series chip.</li>
          <li>macOS 14 Sonoma or later.</li>
        </ul>
      </section>
      <Callout warning>
        Bourbon is designed for Apple Silicon. Intel Macs and macOS releases
        before Sonoma are not supported by this release.
      </Callout>
      <section className="docsSection">
        <h2>What is a Bottle?</h2>
        <p>
          A Bottle is an isolated Windows environment. It keeps its own Windows
          files, settings, installed apps, and configuration, so apps can stay
          separate from one another.
        </p>
        <Image
          className="docsScreenshot"
          src="/assets/bourbon-bottle-explainer.png"
          alt="Bourbon explains that a Bottle is an isolated Windows environment"
          width={1478}
          height={1628}
        />
      </section>
      <section className="docsSection">
        <h2>What is BourbonWine?</h2>
        <p>
          BourbonWine is the runtime Bourbon uses to run Windows software.
          Bourbon downloads it when it is needed; you do not need to install
          Wine separately.
        </p>
      </section>
      <section className="docsSection">
        <h2>Your first launch</h2>
        <p>
          Bourbon checks the required setup items, including Rosetta and
          BourbonWine, then guides you to create your first Bottle and choose a
          Windows installer. Downloads and setup can take a little time,
          especially on a new Mac or a slower connection.
        </p>
      </section>
      <DocLink href="/docs/installing-bourbon">Install Bourbon</DocLink>
    </DocsLayout>
  );
}

function InstallingBourbon() {
  return (
    <DocsLayout slug="installing-bourbon">
      <p className="eyebrow">Installation</p>
      <h1>Install Bourbon on your Mac.</h1>
      <p className="docsLead">
        Public Bourbon downloads are temporarily paused while we validate an
        important runtime update. A corrected public build is expected by the
        end of the week.
      </p>
      <section className="docsSection">
        <h2>Downloads paused</h2>
        <p>
          Please avoid installing the current public build while this work is in
          progress. Diagnostic builds are intended only for approved testers.
        </p>
      </section>
      <section className="docsSection">
        <h2>Homebrew</h2>
        <p>
          Homebrew installation is also paused until the corrected build is
          ready.
        </p>
      </section>
      <Callout>
        If macOS asks for permission on first launch, follow the prompt and
        approve Bourbon only if you downloaded it from the official release
        source.
      </Callout>
      <section className="docsSection">
        <h2>If macOS blocks the app</h2>
        <p>
          A build that is unsigned or not notarized can trigger a Gatekeeper
          warning. Open{" "}
          <strong>System Settings → Privacy &amp; Security</strong>, review the
          warning for Bourbon, and use the available option to open that app if
          you trust its official source. Do not disable Gatekeeper globally.
        </p>
      </section>
    </DocsLayout>
  );
}

function CreatingABottle() {
  return (
    <DocsLayout slug="creating-a-bottle">
      <p className="eyebrow">Bottles</p>
      <h1>Create a dedicated Windows environment.</h1>
      <p className="docsLead">
        A Bottle gives an app or game its own Windows files and settings.
      </p>
      <Image
        className="docsScreenshot"
        src="/assets/bourbon-create-bottle.png"
        alt="Bourbon's Create Bottle form"
        width={1478}
        height={1628}
        priority
      />
      <section className="docsSection">
        <h2>Choose the Bottle details</h2>
        <ul>
          <li>
            <strong>Bottle name:</strong> use the app or game name. If left
            blank, Bourbon names it “My Bottle.”
          </li>
          <li>
            <strong>Bottle type:</strong> choose Gaming, Applications,
            Development, or Advanced as a starting profile.
          </li>
          <li>
            <strong>Windows version:</strong> choose the Windows version the app
            should see. Windows 7 and Windows XP are marked deprecated.
          </li>
          <li>
            <strong>Installer:</strong> optionally choose the Windows installer
            you plan to use. Bourbon can use it after the Bottle is created.
          </li>
          <li>
            <strong>Storage:</strong> keep Bourbon’s default location or select
            a custom folder.
          </li>
        </ul>
      </section>
      <section className="docsSection">
        <h2>Create or Cancel</h2>
        <p>
          Select <strong>Create</strong> to make the Bottle. Bourbon selects the
          new Bottle and takes you to the install flow; if you picked an
          installer, it is ready for that next step. Select{" "}
          <strong>Cancel</strong> to close the form without creating a Bottle.
        </p>
      </section>
      <DocLink href="/docs/installing-windows-apps">
        Install a Windows app
      </DocLink>
    </DocsLayout>
  );
}

function InstallingWindowsApps() {
  return (
    <DocsLayout slug="installing-windows-apps">
      <p className="eyebrow">Windows apps</p>
      <h1>Install software into the right Bottle.</h1>
      <p className="docsLead">
        Start with the installer supplied by the app or game publisher.
      </p>
      <section className="docsSection">
        <h2>Choose an installer</h2>
        <p>
          Open the target Bottle and choose its installer option, then select
          the download you received. Standard Windows installers are usually{" "}
          <code>.exe</code> or <code>.msi</code> files.
        </p>
        <p>
          The current picker also accepts <code>.bat</code>, <code>.zip</code>,{" "}
          <code>.rar</code>, <code>.7z</code>, and <code>.iso</code> files.
          Archive support means Bourbon can select those files; whether the
          contents install or run depends on the software inside.
        </p>
      </section>
      <section className="docsSection">
        <h2>After installation</h2>
        <p>
          Bourbon refreshes the Bottle’s installed-program list after the
          installer finishes. Select the installed program from that Bottle to
          launch it. Keep the app and its dependencies in the same Bottle unless
          you have a reason to isolate them.
        </p>
      </section>
      <Callout warning>
        Compatibility varies. Some Windows apps and games need additional setup,
        dependencies, or a different Bottle configuration, and some may not run.
      </Callout>
      <DocLink href="/docs/troubleshooting">
        Troubleshoot an app that will not launch
      </DocLink>
    </DocsLayout>
  );
}

function BourbonWine() {
  return (
    <DocsLayout slug="bourbonwine">
      <p className="eyebrow">Runtime</p>
      <h1>The runtime behind your Bottles.</h1>
      <p className="docsLead">
        BourbonWine is the runtime Bourbon uses to run Windows software.
      </p>
      <section className="docsSection">
        <h2>Automatic setup</h2>
        <p>
          When BourbonWine is not already available, Bourbon downloads the
          supported runtime automatically during setup. Runtime download
          information is served by the Bourbon Runtime API.
        </p>
      </section>
      <section className="docsSection">
        <h2>Use a local archive if needed</h2>
        <p>
          If the automatic download fails, choose{" "}
          <strong>Choose Local BourbonWine Archive</strong> in the setup flow
          and select a compatible local archive. Bourbon validates the archive
          before installing it.
        </p>
      </section>
      <Callout>
        The runtime is managed by Bourbon. You generally do not need a separate
        Wine installation to create a Bottle or launch an app.
      </Callout>
      <DocLink href="/docs/troubleshooting">
        Fix a runtime download problem
      </DocLink>
    </DocsLayout>
  );
}

function Updates() {
  return (
    <DocsLayout slug="updates">
      <p className="eyebrow">Updates</p>
      <h1>Keep Bourbon current.</h1>
      <p className="docsLead">
        Bourbon uses Sparkle to check for and deliver app updates.
      </p>
      <section className="docsSection">
        <h2>Automatic update checks</h2>
        <p>
          Returning users can receive background update checks. When an update
          is ready, Bourbon presents the available install choices. Depending on
          the update, you may be asked to restart Bourbon to finish installing
          it.
        </p>
      </section>
      <section className="docsSection">
        <h2>Stable and prerelease updates</h2>
        <p>
          Stable updates are the default. Bourbon recognizes beta, prerelease,
          and release-candidate channels, but does not offer them unless you
          explicitly enable prerelease updates in Settings. Major updates
          require confirmation.
        </p>
      </section>
      <section className="docsSection">
        <h2>Homebrew</h2>
        <p>Homebrew installations can also be updated from Terminal:</p>
        <pre>
          <code>brew upgrade bourbon</code>
        </pre>
      </section>
      <Callout warning>
        If an update reports a validation or signature error, do not bypass the
        warning. See troubleshooting, then download again from an official
        source.
      </Callout>
    </DocsLayout>
  );
}

function Troubleshooting() {
  return (
    <DocsLayout slug="troubleshooting">
      <p className="eyebrow">Troubleshooting</p>
      <h1>Work through the common setup problems.</h1>
      <p className="docsLead">
        If an error persists, send a report from Bourbon with the details below.
      </p>
      <section className="docsSection">
        <h2>BourbonWine download failure</h2>
        <p>
          Check your connection, try again, and use a compatible local
          BourbonWine archive from the setup screen if you already have one.
        </p>
        <h2>HTTP or API errors</h2>
        <p>
          These usually indicate a network, service, or response problem. Try
          again later on a reliable connection. Include the exact HTTP status or
          error message in a report.
        </p>
        <h2>Bottle creation failure</h2>
        <p>
          Make sure the chosen storage folder is available and writable, try the
          default Bourbon location, and use a simpler Bottle name if the error
          identifies a path problem.
        </p>
        <h2>A Windows app does not launch</h2>
        <p>
          Confirm you installed it into the intended Bottle, reopen the Bottle,
          and try launching it from Bourbon’s installed-program list.
          Compatibility differs by app; some titles need additional setup or a
          different configuration.
        </p>
        <h2>Update validation or signature errors</h2>
        <p>
          Do not override the error. Quit duplicate copies of Bourbon, download
          again from GitHub Releases, or update through Homebrew if that is how
          you installed it.
        </p>
        <h2>Duplicate or old Bourbon copies</h2>
        <p>
          Keep one active copy in Applications. An older copy in Downloads,
          another folder, or a mounted DMG can make it unclear which version
          macOS is opening.
        </p>
        <h2>Network or offline issues</h2>
        <p>
          Runtime downloads, updates, and report submission need network access.
          You can still work with installed files offline, but setup downloads
          and online checks will wait until you reconnect.
        </p>
      </section>
      <DocLink href="/docs/bug-reporting">Report a problem</DocLink>
    </DocsLayout>
  );
}

function BugReporting() {
  return (
    <DocsLayout slug="bug-reporting">
      <p className="eyebrow">Support</p>
      <h1>Send a useful report without oversharing.</h1>
      <p className="docsLead">
        Bourbon’s built-in Report a Problem flow lets you review what will be
        sent first.
      </p>
      <section className="docsSection">
        <h2>Use Report a Problem</h2>
        <p>
          Open the built-in report feature, choose the report type, describe
          what happened, and select <strong>View Report</strong> before you
          submit. Bourbon does not send reports silently. If the report service
          is unavailable, the app can save a pending report locally for retrying
          later.
        </p>
      </section>
      <section className="docsSection">
        <h2>What diagnostics can include</h2>
        <p>
          You can choose whether to include diagnostics and logs. Diagnostics
          may include the Bourbon version and build, macOS version, Mac model,
          CPU architecture, runtime version, and recent error or crash
          information.
        </p>
        <p>
          Bourbon redacts home-folder paths, common secrets and tokens, license
          tokens, and email addresses unless you explicitly provide a contact
          email. Review the report preview before sending, especially when logs
          are included.
        </p>
      </section>
      <section className="docsSection">
        <h2>What to include</h2>
        <ul>
          <li>Bourbon version</li>
          <li>macOS version and Mac model</li>
          <li>Clear steps that reproduce the issue</li>
          <li>Screenshots and the complete error message</li>
          <li>
            The Windows app or installer name, without sharing private files
          </li>
        </ul>
      </section>
      <section className="docsSection">
        <h2>Community support</h2>
        <p>
          You can also ask in the Bourbon Discord’s bug-report channel. For a
          reproducible product issue, include the same version, system, steps,
          and error details there.
        </p>
        <a className="docsTextLink" href="https://discord.gg/CsqAfs9CnM">
          Open Bourbon Discord <ExternalLink aria-hidden="true" size={16} />
        </a>
      </section>
    </DocsLayout>
  );
}

function FAQ() {
  const items = [
    ["Is Bourbon free?", "Yes. Bourbon is available at no cost."],
    [
      "What Macs are supported?",
      "Apple Silicon Macs with an M-series chip running macOS 14 Sonoma or later."
    ],
    [
      "Does Bourbon include Wine?",
      "Bourbon manages BourbonWine, the runtime it uses to run Windows software. It downloads the runtime when needed."
    ],
    [
      "What is a Bottle?",
      "An isolated Windows environment with its own files, settings, installed apps, and configuration."
    ],
    [
      "What is BourbonWine?",
      "The runtime Bourbon uses to run Windows apps and games."
    ],
    [
      "How do I update?",
      "Use Bourbon’s Sparkle update flow, or run brew upgrade bourbon if you installed with Homebrew."
    ],
    [
      "Where do I report bugs?",
      "Use Report a Problem in Bourbon, or the Bourbon Discord bug-report channel."
    ],
    [
      "Why does my Windows app not work?",
      "Windows compatibility varies. The app may need extra setup or a different Bottle configuration, and some software may not run."
    ],
    [
      "Is Bourbon affiliated with Apple, WineHQ, CodeWeavers, or Whisky?",
      "No. Bourbon is not affiliated with Apple, WineHQ, CodeWeavers, or Whisky."
    ],
    [
      "Where do I get support?",
      "Start with these docs and troubleshooting, then use the built-in report flow or Bourbon Discord for help."
    ]
  ];

  return (
    <DocsLayout slug="faq">
      <p className="eyebrow">FAQ</p>
      <h1>Quick answers about Bourbon.</h1>
      <div className="docsFaq">
        {items.map(([question, answer]) =>
          question === "Where do I get support?" ? (
            <HiddenAdminFaqItem
              key={question}
              question={question}
              answer={answer}
            />
          ) : (
            <section key={question}>
              <h2>{question}</h2>
              <p>{answer}</p>
            </section>
          )
        )}
      </div>
    </DocsLayout>
  );
}

export function DocsPage({ slug }: { slug: DocSlug }) {
  switch (slug) {
    case "home":
      return <DocsHome />;
    case "getting-started":
      return <GettingStarted />;
    case "installing-bourbon":
      return <InstallingBourbon />;
    case "creating-a-bottle":
      return <CreatingABottle />;
    case "installing-windows-apps":
      return <InstallingWindowsApps />;
    case "bourbonwine":
      return <BourbonWine />;
    case "updates":
      return <Updates />;
    case "troubleshooting":
      return <Troubleshooting />;
    case "bug-reporting":
      return <BugReporting />;
    case "faq":
      return <FAQ />;
  }
}
