export const siteConfig = {
  productName: "Bourbon",
  canonicalDomain: "https://getbourbon.app",
  tagline: "Run Windows apps on your Mac with a native macOS feel.",
  currentVersion: "2.0.19",
  minimumMacOSVersion: "14.0",
  githubRepository: "Unblockerfire/Bourbon",
  githubRepositoryUrl: "https://github.com/Unblockerfire/Bourbon",
  releasesPageUrl: "https://github.com/Unblockerfire/Bourbon/releases",
  downloadsPaused: true,
  downloadsPauseMessage:
    "Bourbon downloads are temporarily paused while we validate an important runtime update. We're actively testing the corrected build and expect downloads to return by the end of the week.",
  documentationUrl: "/docs",
  supportUrl: "/support",
  privacyUrl: "/privacy",
  appcastUrl: "https://api.getbourbon.app/updates/stable/appcast.xml",
  runtimeApiUrl: "https://api.getbourbon.app/runtime/latest"
} as const;

export const featureCards = [
  {
    title: "Bottle setup without the terminal",
    description:
      "Create isolated Windows environments, choose a Windows version, and add installers from a guided SwiftUI flow.",
    image: "/assets/bourbon-create-bottle.png",
    alt: "Bourbon create bottle screen with bottle type, Windows version, installer, and storage controls"
  },
  {
    title: "A native home for Windows apps",
    description:
      "Bourbon keeps apps, settings, registry data, dependencies, and shortcuts organized per bottle on macOS.",
    image: "/assets/bourbon-welcome-screen.png",
    alt: "Bourbon welcome screen inviting the user to create a first bottle"
  },
  {
    title: "Compatibility checks before launch",
    description:
      "Imported installers pass through Bourbon's compatibility system before Wine runs them, including safer launch paths for supported embedded app payloads.",
    image: "/assets/bourbon-bottle-explainer.png",
    alt: "Bourbon bottle explanation dialog describing an isolated Windows environment"
  }
] as const;
export const acknowledgments = [
  {
    name: "Bourbon Runtime API",
    purpose:
      "Express service for runtime metadata, update appcasts, and bug report intake.",
    license: "Project license"
  },
  {
    name: "Express",
    purpose: "HTTP routing for the Bourbon runtime API.",
    license: "MIT"
  },
  {
    name: "AWS SDK for JavaScript",
    purpose:
      "S3-compatible request signing for Bourbon runtime downloads stored in R2.",
    license: "Apache-2.0"
  },
  {
    name: "Next.js",
    purpose: "Production React framework for this website.",
    license: "MIT"
  },
  {
    name: "React",
    purpose: "Website UI rendering.",
    license: "MIT"
  },
  {
    name: "TypeScript",
    purpose: "Static typing for the website.",
    license: "Apache-2.0"
  },
  {
    name: "lucide-react",
    purpose: "Accessible interface icons on the website.",
    license: "ISC"
  },
  {
    name: "Caddy",
    purpose: "Single-container host routing for the website and runtime API.",
    license: "Apache-2.0"
  },
  {
    name: "Sparkle",
    purpose: "Bourbon app update support.",
    license: "MIT"
  },
  {
    name: "SemanticVersion",
    purpose: "Version parsing in Bourbon's Swift package.",
    license: "MIT"
  },
  {
    name: "swift-argument-parser",
    purpose: "Command-line interface support for Bourbon tools.",
    license: "Apache-2.0"
  },
  {
    name: "SwiftTextTable",
    purpose: "Terminal table formatting for Bourbon command-line output.",
    license: "MIT"
  },
  {
    name: "Progress.swift",
    purpose: "Swift progress utilities resolved by the app workspace.",
    license: "MIT"
  },
  {
    name: "msync",
    purpose: "Wine synchronization support used by Bourbon's runtime stack.",
    license: "See upstream project"
  },
  {
    name: "DXVK-macOS",
    purpose: "Graphics translation support used by Bourbon's runtime stack.",
    license: "See upstream project"
  },
  {
    name: "MoltenVK",
    purpose: "Vulkan-to-Metal support used by Bourbon's runtime stack.",
    license: "Apache-2.0"
  },
  {
    name: "CrossOver 22.1.1",
    purpose: "Wine technology used by Bourbon's runtime stack.",
    license: "Commercial software"
  },
  {
    name: "Apple Game Porting Toolkit and D3DMetal",
    purpose: "Apple graphics and game-porting technologies used by Bourbon.",
    license: "Apple software license"
  }
] as const;
