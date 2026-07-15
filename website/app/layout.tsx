import type { Metadata, Viewport } from "next";
import { Fraunces, Inter, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";

const fraunces = Fraunces({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-fraunces",
  display: "swap",
});

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const plexMono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-plex-mono",
  display: "swap",
});

const SITE_URL = "https://cachy.vatxzz.workers.dev";
const DESCRIPTION =
  "Cachy turns the reels, videos, articles, and PDFs you send into knowledge you can search, connect, and actually remember. Send it. Forget about it.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Cachy — Don't save content. Catch knowledge.",
  description: DESCRIPTION,
  applicationName: "Cachy",
  keywords: [
    "Cachy",
    "knowledge",
    "save reels",
    "second brain",
    "bookmarks",
    "search by meaning",
  ],
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Cachy",
    title: "Cachy — Don't save content. Catch knowledge.",
    description: DESCRIPTION,
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Cachy — Send it. Forget about it.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Cachy — Don't save content. Catch knowledge.",
    description: DESCRIPTION,
    images: ["/og.png"],
  },
  icons: {
    icon: [{ url: "/icon.svg", type: "image/svg+xml" }],
  },
};

export const viewport: Viewport = {
  themeColor: "#181818",
  colorScheme: "dark",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${fraunces.variable} ${inter.variable} ${plexMono.variable}`}
    >
      <body className="font-sans antialiased">{children}</body>
    </html>
  );
}
