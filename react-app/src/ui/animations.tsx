/**
 * Animation primitives — React port of Flutter's Motion tokens.
 *
 * Tokens (mirrors --motion-* in index.css):
 *   fast    = 180ms  (0.18s)
 *   medium  = 260ms  (0.26s)
 *   stagger = 45ms   (0.045s)
 *   curve   = easeOutCubic → [0.33, 1, 0.68, 1]
 *
 * Every animation here is 180–260ms, ease-out. Only transform/opacity are
 * animated (GPU-cheap, no layout thrash).
 *
 * Requires the `motion` package (`npm install motion`):
 *   import { motion } from 'motion/react';
 *
 * These are building blocks only — existing components are NOT wired to them
 * yet; that refactor is a follow-up. Wrap the app root in <MotionRoot> when
 * adopting, so prefers-reduced-motion is respected.
 */
import { AnimatePresence, MotionConfig, motion } from 'motion/react';
import type { CSSProperties, ReactNode } from 'react';
import type { Transition, Variants } from 'motion/react';

/* ── Tokens ─────────────────────────────────────────────────────────────── */

export const DUR_FAST = 0.18;
export const DUR_MEDIUM = 0.26;
export const STAGGER_STEP = 0.045;
/** easeOutCubic — matches --ease-out in index.css and Flutter's easeOutCubic. */
export const EASE_OUT_CUBIC: [number, number, number, number] = [0.33, 1, 0.68, 1];

export const TRANS_FAST: Transition = { duration: DUR_FAST, ease: EASE_OUT_CUBIC };
export const TRANS_MEDIUM: Transition = { duration: DUR_MEDIUM, ease: EASE_OUT_CUBIC };

/* ── MotionRoot ─────────────────────────────────────────────────────────── */

/** Wrap the app root so `prefers-reduced-motion` disables these animations. */
export function MotionRoot({ children }: { children: ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}

/* ── FadeIn ─────────────────────────────────────────────────────────────── */

/**
 * Fade + slight y-slide on mount. Default 180ms ease-out.
 * Usage: <FadeIn><Card …/></FadeIn>
 */
export function FadeIn({
  children,
  delay = 0,
  y = 8,
  duration = DUR_FAST,
  className,
  style,
}: {
  children: ReactNode;
  /** Delay before the animation starts, in seconds. */
  delay?: number;
  /** Starting vertical offset in px. */
  y?: number;
  /** Duration in seconds (default 0.18). */
  duration?: number;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <motion.div
      className={className}
      style={style}
      initial={{ opacity: 0, y }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration, delay, ease: EASE_OUT_CUBIC }}
    >
      {children}
    </motion.div>
  );
}

/* ── Pressable ──────────────────────────────────────────────────────────── */

/**
 * Generic press wrapper: scales to 0.97 while pressed (180ms ease-out).
 * For real <button>s prefer motion.button with whileTap directly; this is for
 * non-button surfaces (cards, tiles) that act as tap targets.
 */
export function Pressable({
  children,
  onTap,
  scale = 0.97,
  className,
  style,
}: {
  children: ReactNode;
  onTap?: () => void;
  /** Pressed scale (default 0.97). */
  scale?: number;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <motion.div
      className={className}
      style={{ cursor: onTap ? 'pointer' : undefined, ...style }}
      whileTap={{ scale }}
      transition={TRANS_FAST}
      onTap={onTap}
    >
      {children}
    </motion.div>
  );
}

/* ── Stagger ────────────────────────────────────────────────────────────── */

/**
 * Staggers direct <StaggerItem> children on mount, 45ms apart.
 * Matches Flutter's Motion.stagger.
 *
 * Usage:
 *   <Stagger>
 *     {items.map(i => <StaggerItem key={i.id}>…</StaggerItem>)}
 *   </Stagger>
 */
const staggerContainer: Variants = {
  hidden: {},
  show: { transition: { staggerChildren: STAGGER_STEP } },
};

const staggerItem: Variants = {
  hidden: { opacity: 0, y: 8 },
  show: { opacity: 1, y: 0, transition: TRANS_MEDIUM },
};

export function Stagger({
  children,
  className,
  style,
}: {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <motion.div
      className={className}
      style={style}
      variants={staggerContainer}
      initial="hidden"
      animate="show"
    >
      {children}
    </motion.div>
  );
}

/** One child of <Stagger>. Must be a direct child to inherit the stagger. */
export function StaggerItem({
  children,
  className,
  style,
}: {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <motion.div className={className} style={style} variants={staggerItem}>
      {children}
    </motion.div>
  );
}

/* ── TabIndicator ───────────────────────────────────────────────────────── */

/**
 * Layout-animated sliding pill for tab bars. Renders a motion.span sharing
 * `layoutId` across tabs, so the pill glides between them (260ms ease-out).
 *
 * Usage (inside each tab, which must be position:relative):
 *   {active && <TabIndicator id="pill-nav" className="pill-active-bg" />}
 * The pill is absolutely positioned by the caller (e.g. inset-0, rounded-full).
 */
export function TabIndicator({
  id,
  className,
  style,
}: {
  /** Shared layoutId across the tabs in one bar. */
  id: string;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <motion.span
      layoutId={id}
      className={className}
      style={style}
      transition={TRANS_MEDIUM}
    />
  );
}

/* ── Sheet ──────────────────────────────────────────────────────────────── */

/**
 * Bottom sheet with AnimatePresence: scrim fades (180ms), panel slides up
 * from 100% (260ms). Mount <LiquidGlassDefs> once if the panel uses
 * .glass-liquid.
 */
export function Sheet({
  open,
  onClose,
  children,
  className,
  panelClassName,
}: {
  open: boolean;
  onClose?: () => void;
  children: ReactNode;
  /** Extra class on the scrim (fixed overlay). */
  className?: string;
  /** Extra class on the sliding panel. */
  panelClassName?: string;
}) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          key="sheet-scrim"
          className={`sheet-scrim${className ? ` ${className}` : ''}`}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={TRANS_FAST}
          onClick={onClose}
        >
          <motion.div
            key="sheet-panel"
            role="dialog"
            aria-modal="true"
            className={`sheet-panel${panelClassName ? ` ${panelClassName}` : ''}`}
            initial={{ y: '100%' }}
            animate={{ y: '0%' }}
            exit={{ y: '100%' }}
            transition={TRANS_MEDIUM}
            onClick={(e) => e.stopPropagation()}
          >
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/* ── Modal ──────────────────────────────────────────────────────────────── */

/**
 * Centered modal with AnimatePresence: scrim fades (180ms), panel fades +
 * scales from 0.96 with a slight y-slide (260ms).
 */
export function Modal({
  open,
  onClose,
  children,
  className,
  panelClassName,
}: {
  open: boolean;
  onClose?: () => void;
  children: ReactNode;
  /** Extra class on the scrim (fixed overlay). */
  className?: string;
  /** Extra class on the dialog panel. */
  panelClassName?: string;
}) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          key="modal-scrim"
          className={`modal-scrim${className ? ` ${className}` : ''}`}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={TRANS_FAST}
          onClick={onClose}
        >
          <motion.div
            key="modal-panel"
            role="dialog"
            aria-modal="true"
            className={`modal-panel${panelClassName ? ` ${panelClassName}` : ''}`}
            initial={{ opacity: 0, scale: 0.96, y: 8 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96, y: 8 }}
            transition={TRANS_MEDIUM}
            onClick={(e) => e.stopPropagation()}
          >
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/* ── LiquidGlassDefs ────────────────────────────────────────────────────── */

/**
 * Hidden SVG defs for the liquid-glass refraction filter. Mount ONCE near the
 * app root (e.g. inside App) — `.glass-liquid` in glass.css references
 * `url(#liquid-glass)`. Without this, .glass-liquid degrades to plain blur.
 *
 * Chromium-only effect: Safari/Firefox ignore the SVG reference inside
 * backdrop-filter and keep the blur fallback.
 *
 * Tuning knobs: feDisplacementMap `scale` (refraction strength),
 * feTurbulence `baseFrequency` (warp grain size).
 */
export function LiquidGlassDefs() {
  return (
    <svg
      aria-hidden="true"
      focusable="false"
      style={{ position: 'absolute', width: 0, height: 0, overflow: 'hidden' }}
    >
      <defs>
        <filter
          id="liquid-glass"
          x="-20%"
          y="-20%"
          width="140%"
          height="140%"
          colorInterpolationFilters="sRGB"
        >
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.012 0.02"
            numOctaves="2"
            seed="7"
            result="noise"
          />
          <feGaussianBlur in="noise" stdDeviation="3" result="softNoise" />
          <feDisplacementMap
            in="SourceGraphic"
            in2="softNoise"
            scale="22"
            xChannelSelector="R"
            yChannelSelector="G"
            result="refract"
          />
        </filter>
      </defs>
    </svg>
  );
}
