/**
 * Glass surface + ambient background — port of Flutter's
 * ui/core/widgets/glass.dart.
 *
 * AmbientBackground: procedural radial-blob layer placed behind all content so
 * glass surfaces have something rich to blur against.
 * Glass: frosted-glass container (backdrop blur + translucent fill + 0.8px
 * hairline border).
 */
import type { CSSProperties, ReactNode } from 'react';
import './widgets.css';

export function AmbientBackground() {
  return <div className="ambient-bg" aria-hidden />;
}

export function Glass({
  children,
  radius = 0,
  padding,
  blur,
  fill,
  showBorder = true,
  className,
  style,
}: {
  children: ReactNode;
  /** Corner radius in px. Flutter: Glass.card = 18. */
  radius?: number;
  padding?: CSSProperties['padding'];
  /** Override blur sigma (defaults to the --glass-blur token). */
  blur?: number;
  /** Override fill color (defaults to --glass-fill). */
  fill?: string;
  /** Show the hairline border (default true). */
  showBorder?: boolean;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <div
      className={`glass${className ? ` ${className}` : ''}`}
      style={{
        borderRadius: radius,
        padding,
        ...(blur != null ? { backdropFilter: `blur(${blur}px)`, WebkitBackdropFilter: `blur(${blur}px)` } : null),
        ...(fill != null ? { background: fill } : null),
        ...(showBorder ? null : { borderColor: 'transparent' }),
        ...style,
      }}
    >
      {children}
    </div>
  );
}
