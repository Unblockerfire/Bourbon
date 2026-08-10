import type { Metadata } from "next";

import { acknowledgments, siteConfig } from "@/lib/siteConfig";

export const metadata: Metadata = {
  title: "Acknowledgments",
  description: `Open-source acknowledgments and dependency notices for ${siteConfig.productName}.`,
  alternates: {
    canonical: "/acknowledgments"
  }
};

export default function AcknowledgmentsPage() {
  return (
    <main id="main" className="pageShell">
      <section className="pageHero">
        <p className="eyebrow">Acknowledgments</p>
        <h1>Software Bourbon builds on.</h1>
        <p>
          This page lists dependencies used by Bourbon, the runtime API, or this
          website. It intentionally excludes unrelated website code and assets
          from other projects.
        </p>
      </section>

      <section className="ackTable" aria-label="Dependency acknowledgments">
        <div className="ackHeader" role="row">
          <span>Name</span>
          <span>Used for</span>
          <span>License</span>
        </div>
        {acknowledgments.map((item) => (
          <article className="ackRow" key={item.name}>
            <h2>{item.name}</h2>
            <p>{item.purpose}</p>
            <span>{item.license}</span>
          </article>
        ))}
      </section>
    </main>
  );
}
