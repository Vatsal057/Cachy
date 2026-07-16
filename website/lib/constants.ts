/** Central content + link constants for the Cachy site. */

export const CACHY = {
  name: "Cachy",
  handle: "@cachy.app",
  tagline: "Send it. Forget about it.",
  email: "hello@cachy.app",
  // Distribution: sideloaded APK + hosted web app (no app stores).
  download: {
    // Pinned to the release tag on purpose: the repo also hosts the model
    // release, so `releases/latest` is unreliable. Bump on each app version.
    apk: "https://github.com/Vatsal057/Cachy/releases/download/v1.0.0/Cachy-v1.0.0-arm64-v8a.apk",
    web: "https://vatxzz-cachy.hf.space",
  },
  repo: "https://github.com/Vatsal057/Cachy",
} as const;

export const NAV_LINKS = [
  { label: "Features", href: "#features" },
  { label: "Privacy", href: "#privacy" },
  { label: "FAQ", href: "#faq" },
] as const;

/** Platform-independence evidence — a quiet row, not a feature list. */
export const SOURCES = [
  "Instagram",
  "YouTube",
  "X",
  "Medium",
  "Substack",
  "LinkedIn",
  "PDFs",
  "Articles",
] as const;

export const HOW_IT_WORKS = [
  {
    key: "catch",
    title: "Catch",
    body: "Send anything to Cachy from wherever it lives. The easiest way: DM @cachy.app on Instagram.",
  },
  {
    key: "understand",
    title: "Understand",
    body: "Cachy reads it and pulls out the summary, the key ideas, and what to do next.",
  },
  {
    key: "remember",
    title: "Remember",
    body: "It lands in a library you can actually search — by meaning, not filenames.",
  },
] as const;

export const FEATURES = [
  {
    key: "send",
    title: "Send anything",
    body: "A reel, a video, an article, a PDF. If you can share it, Cachy can keep it.",
  },
  {
    key: "search",
    title: "Search by meaning",
    body: "Ask for the idea, not the filename. Cachy finds it even when you forgot the words.",
  },
  {
    key: "connect",
    title: "Everything connects",
    body: "Related ideas link themselves, so one thing you saved leads to the next.",
  },
  {
    key: "keep",
    title: "Never lose it again",
    body: "No graveyard of bookmarks. What you send stays findable for good.",
  },
] as const;

export const FAQS = [
  {
    q: "What can I save?",
    a: "Reels, videos, articles, PDFs, posts, and web pages. If it has a link or you can share it, Cachy can turn it into something you'll find later.",
  },
  {
    q: "Does it support Instagram?",
    a: "Yes. The easiest way to use Cachy is to DM a reel or post to @cachy.app. It's the quickest on-ramp, not the only one.",
  },
  {
    q: "Can I save YouTube?",
    a: "Yes. Send a YouTube link and Cachy pulls out the summary, key points, and anything worth acting on.",
  },
  {
    q: "Can I search everything?",
    a: "Yes. Search works by meaning across your whole library, so you can find an idea even when you don't remember where it came from.",
  },
  {
    q: "Is it free?",
    a: "Cachy is free to use. It's built free-first, so it keeps working even when AI limits are reached.",
  },
  {
    q: "Why not just use Instagram saves?",
    a: "Saves are a pile you never reopen. Cachy reads what you send, structures it, connects it, and makes it searchable — so it's knowledge, not another graveyard.",
  },
] as const;
