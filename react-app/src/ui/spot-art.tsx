/**
 * SpotArt — the remaining ports of Flutter's ui/core/widgets/spot_art.dart.
 * Hand-drawn spot illustrations, one bespoke motif per screen: line-art in
 * the screen's own ink, calm and low-chroma, deliberately a little irregular.
 * (CaptureSpot, StructureSpot and GraphSpot already live in the onboarding
 * feature; these five complete the set.)
 */
import type { ReactNode } from 'react';
import './widgets.css';

function SpotSvg({
  width,
  height,
  viewBox,
  color,
  children,
}: {
  width: number;
  height: number;
  viewBox?: string;
  color?: string;
  children: ReactNode;
}) {
  return (
    <svg
      width={width}
      height={height}
      viewBox={viewBox ?? `0 0 ${width} ${height}`}
      aria-hidden
      style={{ overflow: 'visible' }}
    >
      <g
        stroke={color ?? 'var(--spot-ink)'}
        strokeWidth={1.7}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      >
        {children}
      </g>
    </svg>
  );
}

const RAD = 57.2958;

/* ── Library: a wall of overlapping card faces (108×78) ── */

export function LibrarySpot({ color }: { color?: string }) {
  const cx = 54;
  const cy = 39;
  const cards = [
    { dx: -22, dy: 2, angle: -0.16, lines: false },
    { dx: 20, dy: -3, angle: 0.13, lines: false },
    { dx: -1, dy: 0, angle: -0.02, lines: true },
  ];
  return (
    <SpotSvg width={108} height={78} color={color}>
      {cards.map((c, i) => (
        <g
          key={i}
          transform={`translate(${cx + c.dx} ${cy + c.dy}) rotate(${(c.angle * RAD).toFixed(2)})`}
        >
          <rect x={-26} y={-34} width={52} height={68} rx={7} />
          {c.lines ? (
            <>
              <line x1={-16} y1={14} x2={16} y2={14} />
              <line x1={-16} y1={22} x2={6} y2={22} />
            </>
          ) : null}
        </g>
      ))}
    </SpotSvg>
  );
}

/* ── Collections: nested folders (108×76) ── */

export function CollectionsSpot({ color }: { color?: string }) {
  const cx = 54;
  const cy = 38;
  const folders = [
    { dx: 2, dy: -10, angle: 0.04 },
    { dx: -2, dy: 8, angle: -0.05 },
  ];
  return (
    <SpotSvg width={108} height={76} color={color}>
      {folders.map((f, i) => (
        <path
          key={i}
          transform={`translate(${cx + f.dx} ${cy + f.dy}) rotate(${(f.angle * RAD).toFixed(2)})`}
          d="M -30 -14 L -10 -14 L -4 -22 L 26 -22 L 30 20 L -30 20 Z"
        />
      ))}
    </SpotSvg>
  );
}

/* ── Actions: a checklist with one ticked box (112×70) ── */

export function ActionsSpot({ color }: { color?: string }) {
  const cx = 28;
  const cy = 35;
  return (
    <SpotSvg width={112} height={70} color={color}>
      {[0, 1, 2].map((i) => {
        const y = cy - 24 + i * 24;
        const len = i === 1 ? 30 : 44;
        return (
          <g key={i}>
            <rect x={cx - 9} y={y - 9} width={18} height={18} rx={4} />
            {i === 0 ? (
              <path d={`M ${cx - 4} ${y} L ${cx - 1} ${y + 5} L ${cx + 6} ${y - 6}`} />
            ) : null}
            <line x1={cx + 18} y1={y} x2={cx + 18 + len} y2={y} />
          </g>
        );
      })}
    </SpotSvg>
  );
}

/* ── Chat: two speech bubbles (112×78) ── */

export function ChatSpot({ color }: { color?: string }) {
  const cx = 56;
  const cy = 39;
  const bx = cx - 44;
  const by = cy - 8;
  const c = color ?? 'var(--spot-ink)';
  return (
    <SpotSvg width={112} height={78} color={color}>
      <rect x={cx - 6} y={cy - 34} width={48} height={30} rx={12} />
      <rect x={bx} y={by} width={56} height={34} rx={13} />
      <path d={`M ${bx + 14} ${by + 34} L ${bx + 8} ${by + 44} L ${bx + 24} ${by + 34}`} />
      {[0, 1, 2].map((i) => (
        <circle
          key={i}
          cx={bx + 16 + i * 12}
          cy={by + 17}
          r={2.1}
          fill={c}
          stroke="none"
        />
      ))}
    </SpotSvg>
  );
}

/* ── Catalog: a book and a film frame (112×74) ── */

export function CatalogSpot({ color }: { color?: string }) {
  const cx = 56;
  const cy = 37;
  return (
    <SpotSvg width={112} height={74} color={color}>
      <g transform={`translate(${cx - 30} ${cy}) rotate(${(-0.1 * RAD).toFixed(2)})`}>
        <rect x={-18} y={-26} width={36} height={52} rx={4} />
        <line x1={-10} y1={-26} x2={-10} y2={26} />
      </g>
      <g transform={`translate(${cx + 26} ${cy + 2}) rotate(${(0.08 * RAD).toFixed(2)})`}>
        <rect x={-22} y={-20} width={44} height={40} rx={4} />
        {[-22, 22].map((x) =>
          [0, 1, 2].map((i) => {
            const y = -14 + i * 12;
            return <line key={`${x}-${i}`} x1={x - 3} y1={y} x2={x + 3} y2={y} />;
          }),
        )}
      </g>
    </SpotSvg>
  );
}
