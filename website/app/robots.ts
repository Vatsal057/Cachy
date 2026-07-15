import type { MetadataRoute } from "next";

/** Static robots.txt — generated at build for the export. */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: "https://cachy.vatxzz.workers.dev/sitemap.xml",
  };
}
