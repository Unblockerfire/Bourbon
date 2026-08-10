import Image from "next/image";
import Link from "next/link";
import {
  Github,
  HeartHandshake,
  MessageCircle,
  ShieldCheck
} from "lucide-react";

import { siteConfig } from "@/lib/siteConfig";
import { DownloadButton } from "./DownloadButton";

export function SiteNav() {
  return (
    <header className="siteHeader">
      <Link className="brandMark" href="/" aria-label="Bourbon home">
        <Image
          src="/assets/bourbon-app-icon-20260809.png"
          alt=""
          width={44}
          height={44}
          priority
        />
        <span>{siteConfig.productName}</span>
      </Link>
      <nav aria-label="Primary navigation" className="navLinks">
        <Link href="/download">Download</Link>
        <Link href="/docs">Docs</Link>
        <Link href="/support">Support</Link>
        <Link href="/privacy">Privacy</Link>
        <a href={siteConfig.githubRepositoryUrl} aria-label="Bourbon on GitHub">
          <Github aria-hidden="true" size={20} />
        </a>
      </nav>
      <div className="navActions">
        `n{" "}
        <Link
          className="iconLink"
          href="/discord"
          aria-label="Join Bourbon on Discord"
        >
          `n <MessageCircle aria-hidden="true" size={19} />
          `n{" "}
        </Link>
        <Link
          className="iconLink"
          href="/acknowledgments"
          aria-label="Acknowledgments"
        >
          <HeartHandshake aria-hidden="true" size={19} />
        </Link>
        <Link className="iconLink" href="/privacy" aria-label="Privacy">
          <ShieldCheck aria-hidden="true" size={19} />
        </Link>
        <DownloadButton compact />
      </div>
    </header>
  );
}
