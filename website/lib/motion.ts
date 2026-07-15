import type { Variants } from "framer-motion";

/** Ease-out only. No bounce, no elastic — Cachy's motion register. */
export const EASE_OUT = [0.16, 1, 0.3, 1] as const;
export const EASE_OUT_QUINT = [0.22, 1, 0.36, 1] as const;

/** A single reveal used across sections, tuned per-use via custom delay. */
export const reveal: Variants = {
  hidden: { opacity: 0, y: 24 },
  show: (delay = 0) => ({
    opacity: 1,
    y: 0,
    transition: { duration: 0.7, ease: EASE_OUT, delay },
  }),
};

export const revealStagger: Variants = {
  hidden: {},
  show: {
    transition: { staggerChildren: 0.1, delayChildren: 0.05 },
  },
};

export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 16 },
  show: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: EASE_OUT },
  },
};

/** Standard viewport trigger: fire once, ~25% in view. */
export const VIEWPORT = { once: true, amount: 0.25 } as const;
