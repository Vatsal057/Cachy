/**
 * Brand mark — SVG port of Flutter's CachyGlyph / CachyWordmark (brand.dart).
 * The "catch" glyph: a U bracket cradling a falling reel square.
 */
import './widgets.css';

export function CachyGlyph({
  size = 28,
  color,
  reelColor,
  reelDrop = 1,
}: {
  size?: number;
  color?: string;
  reelColor?: string;
  /**
   * 0 = reel at the top, 1 = resting in the bracket (used by the splash
   * animation in Flutter's brand.dart).
   */
  reelDrop?: number;
}) {
  const w = 100;
  const h = 100;
  const stroke = w * 0.13;
  const bracket = color ?? 'var(--accent)';
  const t = Math.min(1, Math.max(0, reelDrop));
  // Flutter: topY = h*0.06, restY = h*0.50.
  const cy = h * 0.06 + (h * 0.5 - h * 0.06) * t;
  const reelSize = w * 0.3;
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" aria-hidden>
      <path
        d={`M ${w * 0.18} ${h * 0.3} L ${w * 0.18} ${h * 0.66} A ${w * 0.16} ${
          w * 0.16
        } 0 0 0 ${w * 0.34} ${h * 0.82} L ${w * 0.66} ${h * 0.82} A ${w * 0.16} ${
          w * 0.16
        } 0 0 0 ${w * 0.82} ${h * 0.66} L ${w * 0.82} ${h * 0.3}`}
        fill="none"
        stroke={bracket}
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect
        x={(w * 0.5 - reelSize / 2).toFixed(2)}
        y={(cy - reelSize / 2).toFixed(2)}
        width={reelSize}
        height={reelSize}
        rx={(reelSize * 0.32).toFixed(2)}
        fill={reelColor ?? bracket}
        opacity={reelColor ? 1 : 0.55}
      />
    </svg>
  );
}

/** Full wordmark: glyph + "cachy" in the serif display face. */
export function CachyWordmark({ size = 26 }: { size?: number }) {
  return (
    <span className="brand-wordmark">
      <CachyGlyph size={size * 1.08} />
      <span className="brand-wordmark-text" style={{ fontSize: size }}>
        cachy
      </span>
    </span>
  );
}
