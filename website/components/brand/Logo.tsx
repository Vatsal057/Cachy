import type { CSSProperties } from "react";

/**
 * The Cachy "catch" glyph: a U-bracket cradling a falling reel square.
 * Ported from the app's CachyGlyph (app/lib/ui/core/brand.dart). The reel
 * position is driven by `reelDrop` (0 = top, 1 = resting) so the same mark
 * can animate in the hero and demo.
 */
export function CachyGlyph({
  size = 28,
  className,
  bracketColor = "#96A885",
  reelColor = "rgba(150,168,133,0.5)",
  reelDrop = 1,
  style,
}: {
  size?: number;
  className?: string;
  bracketColor?: string;
  reelColor?: string;
  reelDrop?: number;
  style?: CSSProperties;
}) {
  const V = 32;
  const drop = Math.max(0, Math.min(1, reelDrop));
  const topY = V * 0.06;
  const restY = V * 0.5;
  const cy = topY + (restY - topY) * drop;
  const reelSize = V * 0.3;

  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${V} ${V}`}
      fill="none"
      className={className}
      style={style}
      aria-hidden="true"
      focusable="false"
    >
      <path
        d="M5.76 9.6 L5.76 21.12 A5.12 5.12 0 0 0 10.88 26.24 L21.12 26.24 A5.12 5.12 0 0 0 26.24 21.12 L26.24 9.6"
        stroke={bracketColor}
        strokeWidth={4.16}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect
        x={V * 0.5 - reelSize / 2}
        y={cy - reelSize / 2}
        width={reelSize}
        height={reelSize}
        rx={reelSize * 0.32}
        fill={reelColor}
      />
    </svg>
  );
}

/** Glyph + "cachy" wordmark in the serif display face. */
export function Wordmark({
  size = 22,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    <span className={`inline-flex items-center gap-2 ${className ?? ""}`}>
      <CachyGlyph size={size * 1.15} />
      <span
        className="font-display font-semibold text-ink"
        style={{ fontSize: size, letterSpacing: "-0.03em" }}
      >
        cachy
      </span>
    </span>
  );
}
