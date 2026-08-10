import Link from "next/link";
import { ArrowLeft } from "lucide-react";

export default function NotFound() {
  return (
    <main id="main" className="pageShell notFound">
      <section className="pageHero">
        <p className="eyebrow">404</p>
        <h1>This bottle is empty.</h1>
        <p>The page you were looking for is not part of the Bourbon website.</p>
        <Link className="button buttonPrimary" href="/">
          <ArrowLeft aria-hidden="true" size={18} />
          <span>Back to home</span>
        </Link>
      </section>
    </main>
  );
}
