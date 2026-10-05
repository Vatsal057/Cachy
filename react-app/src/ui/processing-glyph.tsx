/**
 * ProcessingGlyph — port of Flutter's ui/core/widgets/processing_glyph.dart.
 * The signature "working" mark: a center badge carrying a spark glyph, haloed
 * by three concentric rings that ripple outward — the calm pulse shown while
 * a reel is processed.
 */
import type { CSSProperties } from 'react';
import { Sparkle } from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import './widgets.css';

const RING_COUNT = 3;
const CYCLE_MS = 2400;

export function ProcessingGlyph({
  size = 132,
  icon: GlyphIcon = Sparkle as Icon,
  badgeColor,
  iconColor,
}: {
  size?: number;
  icon?: Icon;
  /**
   * Overrides the badge fill (defaults to the accent). Lets the glyph carry
   * the detected source platform's brand color.
   */
  badgeColor?: string;
  /** Icon color on the badge (defaults to the accent's on-color). */
  iconColor?: string;
}) {
  const color = badgeColor ?? 'var(--accent)';
  const badge = size * 0.42;

  return (
    <div
      className="processing-glyph"
      style={{ width: size, height: size }}
      role="status"
      aria-label="Working"
    >
      {Array.from({ length: RING_COUNT }).map((_, i) => (
        <span
          key={i}
          className="pg-ring"
          aria-hidden
          style={
            {
              width: badge,
              height: badge,
              borderColor: color,
              animationDelay: `${(-(i / RING_COUNT) * (CYCLE_MS / 1000)).toFixed(3)}s`,
              animationDuration: `${CYCLE_MS}ms`,
            } as CSSProperties
          }
        />
      ))}
      <span
        className="pg-badge"
        style={{ width: badge, height: badge, background: color }}
      >
        <GlyphIcon
          size={badge * 0.5}
          weight="regular"
          color={iconColor ?? 'var(--on-accent)'}
          aria-hidden
        />
      </span>
    </div>
  );
}
