import type { MetadataRoute } from "next";

/** Single-page marketing site — one entry. */
export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: "https://cachy.app",
      lastModified: new Date(),
      changeFrequency: "monthly",
      priority: 1,
    },
  ];
}
