/**
 * SplitPane — port of Flutter's ui/core/widgets/split_pane.dart.
 * A master-detail layout with a draggable divider between a list panel and a
 * detail panel. The list panel occupies `fraction` of the available width,
 * clamped to [280px, 50% of the width].
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import type { PointerEvent as RPointerEvent, ReactNode } from 'react';
import './widgets.css';

/**
 * Resolves the list-panel width for a split pane given the availableWidth and
 * the requested fraction. Pure — mirrors the Dart top-level function.
 */
export function resolveSplitListWidth(
  availableWidth: number,
  fraction: number,
): number {
  return Math.min(Math.max(availableWidth * fraction, 280), availableWidth * 0.5);
}

export function SplitPane({
  list,
  detail,
  fraction,
  onFractionChanged,
  dividerColor,
}: {
  /** The list (master) panel, shown on the leading side. */
  list: ReactNode;
  /** The detail panel, shown on the trailing side. */
  detail: ReactNode;
  /** The list-panel width as a fraction of the available width. */
  fraction: number;
  /** Called with the new fraction as the divider is dragged. */
  onFractionChanged: (fraction: number) => void;
  /** Color of the 1px divider line (defaults to the hairline token). */
  dividerColor?: string;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const dragState = useRef<{ startX: number; startWidth: number } | null>(null);

  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    const compute = () => setWidth(el.clientWidth);
    compute();
    const ro = new ResizeObserver(compute);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const listWidth = resolveSplitListWidth(width, fraction);

  const onPointerDown = useCallback(
    (e: RPointerEvent) => {
      (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
      dragState.current = { startX: e.clientX, startWidth: listWidth };
    },
    [listWidth],
  );

  const onPointerMove = useCallback(
    (e: RPointerEvent) => {
      const d = dragState.current;
      if (!d || width <= 0) return;
      const newWidth = Math.min(
        Math.max(d.startWidth + (e.clientX - d.startX), 280),
        width * 0.5,
      );
      onFractionChanged(newWidth / width);
    },
    [width, onFractionChanged],
  );

  const onPointerUp = useCallback(() => {
    dragState.current = null;
  }, []);

  return (
    <div className="split-pane" ref={rootRef}>
      <div className="split-list" style={{ width: listWidth }}>
        {list}
      </div>
      <div
        className="split-divider"
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize panels"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      >
        <span
          className="split-divider-line"
          style={dividerColor ? { background: dividerColor } : undefined}
          aria-hidden
        />
      </div>
      <div className="split-detail">{detail}</div>
    </div>
  );
}
