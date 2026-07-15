import type { Config } from "tailwindcss";

/**
 * Cachy — "calm editorial glass, after dark".
 * Deep charcoal world · warm cream ink · one muted sage accent.
 * Tokens mirror the Flutter app's Brand layer (app/lib/ui/core/brand.dart)
 * so the site and product read as one.
 */
const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Dark world — deep charcoal
        ground: "#181818",
        raised: "#222120",
        raised2: "#2A2927",
        // Warm cream ink
        ink: "#EDE8DF",
        muted: "#9A928A",
        // Accent — muted sage, low chroma
        sage: "#96A885",
        "sage-strong": "#A8BA96",
      },
      fontFamily: {
        display: ["var(--font-fraunces)", "Georgia", "serif"],
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
        mono: ["var(--font-plex-mono)", "ui-monospace", "monospace"],
      },
      letterSpacing: {
        display: "-0.03em",
      },
      borderRadius: {
        "4xl": "2rem",
      },
      maxWidth: {
        content: "1200px",
        prose: "68ch",
      },
      boxShadow: {
        soft: "0 4px 24px -8px rgba(0,0,0,0.5)",
        lift: "0 12px 48px -16px rgba(0,0,0,0.6)",
      },
      transitionTimingFunction: {
        "out-quint": "cubic-bezier(0.22, 1, 0.36, 1)",
        "out-expo": "cubic-bezier(0.16, 1, 0.3, 1)",
      },
      zIndex: {
        nav: "50",
        overlay: "60",
      },
    },
  },
  plugins: [],
};

export default config;
