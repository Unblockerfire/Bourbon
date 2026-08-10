export default function AdminLayout({
  children
}: Readonly<{ children: React.ReactNode }>) {
  return <div className="adminShell">{children}</div>;
}
