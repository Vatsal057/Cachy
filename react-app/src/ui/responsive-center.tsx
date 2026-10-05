/**
 * ResponsiveCenter — port of Flutter's ui/core/widgets/responsive_center.dart.
 * Centers and caps single-column content on wide viewports. On
 * desktop-width viewports (>= 600px) the child is horizontally centered and
 * constrained to at most maxWidth (default 680, the reading column). On
 * narrower viewports it is a no-op: full-width, left-aligned.
 */
import type { CSSProperties, ReactNode } from 'react';
import './widgets.css';

export function ResponsiveCenter({
  children,
  maxWidth = 680,
  padding,
  className,
}: {
  children: ReactNode;
  /** Maximum content width applied on wide viewports. */
  maxWidth?: number;
  /** Padding applied around the child in both layout modes. */
  padding?: CSSProperties['padding'];
  className?: string;
}) {
  return (
    <div
      className={`responsive-center${className ? ` ${className}` : ''}`}
      style={
        {
          '--rc-max': `${maxWidth}px`,
          padding,
        } as CSSProperties
      }
    >
      {children}
    </div>
  );
}
