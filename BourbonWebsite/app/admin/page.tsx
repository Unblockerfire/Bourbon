import type { Metadata } from "next";
import { Boxes, FileWarning, LockKeyhole, ShieldCheck } from "lucide-react";
import { AdminLicenseModeration } from "@/components/AdminLicenseModeration";
import { AdminLogoutButton } from "@/components/AdminLogoutButton";
import { AdminReports } from "@/components/AdminReports";
import { requireBourbonAdmin } from "@/lib/adminAuth";
import type { FirebaseBrowserConfig } from "@/lib/firebase/client";

export const metadata: Metadata = {
  title: "Bourbon Administration",
  robots: { index: false, follow: false }
};
function firebaseConfig(): FirebaseBrowserConfig | null {
  const {
    NEXT_PUBLIC_FIREBASE_API_KEY: apiKey,
    NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN: authDomain,
    NEXT_PUBLIC_FIREBASE_PROJECT_ID: projectId,
    NEXT_PUBLIC_FIREBASE_APP_ID: appId
  } = process.env;
  return apiKey && authDomain && projectId && appId
    ? { apiKey, authDomain, projectId, appId }
    : null;
}
export default async function Page() {
  await requireBourbonAdmin();
  return (
    <main className="adminWorkspace">
      <header className="adminTopbar">
        <div className="adminBrand">
          <span className="adminBrandMark">
            <Boxes size={17} />
          </span>
          <span>
            <strong>Bourbon</strong>
            <small>Developer Console</small>
          </span>
        </div>
        <AdminLogoutButton firebaseConfig={firebaseConfig()} />
      </header>
      <div className="adminFrame">
        <aside className="adminSidebar" aria-label="Developer console sections">
          <p className="adminSidebarLabel">Workspace</p>
          <div className="adminNavItem adminNavItemActive">
            <ShieldCheck size={16} /> Moderation
          </div>
          <div className="adminNavItem">
            <FileWarning size={16} /> Reports
          </div>
          <div className="adminSidebarStatus">
            <span /> Authenticated
          </div>
        </aside>
        <section className="adminContent">
          <div className="adminTitleRow">
            <div>
              <p className="adminKicker">Administration</p>
              <h1>License Moderation</h1>
              <p>Review license status and manage moderation actions.</p>
            </div>
            <span className="adminAccessBadge">
              <LockKeyhole size={13} /> Owner access
            </span>
          </div>
          <AdminLicenseModeration />
          <section
            className="adminPanel adminReportsPanel"
            aria-labelledby="report-intake-heading"
          >
            <div className="adminPanelHeading">
              <div>
                <h2 id="report-intake-heading">Report Intake</h2>
                <p>Live summaries from the protected Bourbon Runtime API.</p>
              </div>
              <span className="adminLiveBadge">
                <span /> Live
              </span>
            </div>
            <AdminReports />
          </section>
        </section>
      </div>
    </main>
  );
}
