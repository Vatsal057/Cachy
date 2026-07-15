# Cachy — Official Website

The marketing landing site for Cachy. _Send it. Forget about it._

Built to convince a visitor to download Cachy in ~60 seconds through visual
storytelling. Platform-agnostic positioning: Instagram is the recognizable
demo, not the definition.

## Stack

- **Next.js 14** (App Router) · **TypeScript**
- **Tailwind CSS** — design tokens mirror the Flutter app's brand layer
- **Framer Motion** — ease-out only, full `prefers-reduced-motion` fallbacks
- **Lucide** — all icons

## Design language

"Calm editorial glass, after dark." Deep charcoal ground (`#181818`), warm
cream ink (`#EDE8DF`), one muted sage accent (`#96A885`). Fraunces (display) +
Inter (body) + IBM Plex Mono (labels). No gradients, no neon, no glow. Glass
only on the nav.

## Develop

```bash
npm install
npm run dev      # http://localhost:3000
```

## Build

```bash
npm run build
npm run start
```

## Structure

```
app/               # layout, page, globals, icon, OG image, metadata
components/
  brand/           # CachyGlyph + wordmark (ported from the app)
  ui/              # Button, Container, Reveal, PhoneMockup
  sections/        # Navbar, Hero, SourceRow, Problem, Solution,
                   # HowItWorks, Features, InteractiveDemo, Privacy,
                   # FAQ, FinalCTA, Footer
lib/               # constants (copy/links), motion tokens, reduced-motion hook
```

Section order and behavior track `.kiro/specs/cachy-website/requirements.md`.

## Before shipping

- Set real URLs in `lib/constants.ts` (`download.apk`, `download.web`, `repo`,
  `email`) and `SITE_URL` in `app/layout.tsx`.
- Consider upgrading Next.js to a fully-patched major (see repo security notes).
  The current 14.2.x line carries advisories that only affect self-hosted
  servers using middleware / the image optimizer / i18n — none of which this
  static page uses.
