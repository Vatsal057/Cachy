import { useRef, useState } from 'react';
import {
  ArrowRight,
  Bookmark,
  CheckCircle,
  Link as LinkIcon,
  ListDashes,
  MapPin,
} from 'phosphor-react';
import './Onboarding.css';

/* ------------------------------------------------------------------ */
/* Brand mark — port of CachyGlyph / CachyWordmark (brand.dart)         */
/* ------------------------------------------------------------------ */

function CachyGlyphSvg({ size, animateReel = false }: { size: number; animateReel?: boolean }) {
  const w = size;
  const h = size;
  const stroke = w * 0.13;
  const bracket = '#96A885';
  const reel = 'rgba(150,168,133,0.55)';
  // U-bracket path: M(0.18,0.30) L(0.18,0.66) arc→(0.34,0.82) L(0.66,0.82) arc→(0.82,0.66) L(0.82,0.30)
  const r = w * 0.16;
  const d = [
    `M ${w * 0.18} ${h * 0.3}`,
    `L ${w * 0.18} ${h * 0.66}`,
    `A ${r} ${r} 0 0 0 ${w * 0.34} ${h * 0.82}`,
    `L ${w * 0.66} ${h * 0.82}`,
    `A ${r} ${r} 0 0 0 ${w * 0.82} ${h * 0.66}`,
    `L ${w * 0.82} ${h * 0.3}`,
  ].join(' ');
  const reelSize = w * 0.3;
  const cy = h * 0.5; // reelDrop = 1 (resting)
  const rr = reelSize * 0.32;
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} aria-hidden>
      <path
        d={d}
        fill="none"
        stroke={bracket}
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <g className={animateReel ? 'splash-reel' : undefined}>
        <rect
          x={w * 0.5 - reelSize / 2}
          y={cy - reelSize / 2}
          width={reelSize}
          height={reelSize}
          rx={rr}
          fill={reel}
        />
      </g>
    </svg>
  );
}

function CachyWordmark({ size }: { size: number }) {
  return (
    <span className="onboarding-wordmark">
      <CachyGlyphSvg size={size * 1.08} />
      <span style={{ fontSize: size }}>cachy</span>
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Spot illustrations — ports of spot_art.dart painters                 */
/* ------------------------------------------------------------------ */

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
  color: string;
  children: React.ReactNode;
}) {
  return (
    <svg
      width={width}
      height={height}
      viewBox={viewBox ?? `0 0 ${width} ${height}`}
      aria-hidden
      style={{ overflow: 'visible' }}
    >
      <g stroke={color} strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round" fill="none">
        {children}
      </g>
    </svg>
  );
}

const spotFill = (color: string) => color.replace(/[\d.]+\)$/, '0.18)');

/** Page 1: a link dropping into a card (CaptureSpot, 120×88). */
function CaptureSpot({ color }: { color: string }) {
  const cx = 60;
  const cy = 44;
  const fill = spotFill(color);
  return (
    <SpotSvg width={120} height={88} color={color}>
      <g transform={`translate(${cx - 28} ${cy}) rotate(-3.44)`}>
        <rect x={-22} y={-28} width={44} height={56} rx={6} />
        <line x1={-22} y1={-16} x2={22} y2={-16} />
        <circle cx={-15} cy={-22} r={1.8} fill={color} stroke="none" />
        <circle cx={-9} cy={-22} r={1.8} fill={color} stroke="none" />
        <line x1={-3} y1={-22} x2={14} y2={-22} />
        <rect x={-16} y={-10} width={32} height={20} rx={4} fill={fill} stroke="none" />
        <line x1={-16} y1={16} x2={10} y2={16} />
      </g>
      <g transform={`translate(${cx + 26} ${cy + 2}) rotate(2.29)`}>
        <rect x={-24} y={-30} width={48} height={60} rx={8} />
        <rect x={-18} y={-22} width={24} height={8} rx={4} fill={fill} stroke="none" />
        {[0, 1, 2].map((i) => {
          const y = -6 + i * 14;
          const len = i === 2 ? 18 : 28;
          return (
            <g key={i}>
              <circle cx={-15} cy={y} r={2} fill={color} stroke="none" />
              <line x1={-9} y1={y} x2={-9 + len} y2={y} />
            </g>
          );
        })}
      </g>
    </SpotSvg>
  );
}

/** Page 2: a card resolved into labelled blocks (StructureSpot, 120×88). */
function StructureSpot({ color }: { color: string }) {
  const cx = 54;
  const cy = 40;
  const fill = spotFill(color);
  return (
    <SpotSvg width={120} height={88} viewBox="0 0 108 80" color={color}>
      <rect x={cx - 32} y={cy - 36} width={64} height={72} rx={8} />
      <rect x={cx - 24} y={cy - 28} width={22} height={8} rx={4} fill={fill} stroke="none" />
      {[0, 1, 2].map((i) => {
        const y = cy - 8 + i * 14;
        const len = i === 2 ? 22 : 34;
        return (
          <g key={i}>
            <circle cx={cx - 19} cy={y} r={2.4} fill={color} stroke="none" />
            <line x1={cx - 12} y1={y} x2={cx - 12 + len} y2={y} />
          </g>
        );
      })}
    </SpotSvg>
  );
}

/** Page 3: connected nodes (GraphSpot). Painter draws in 112×80; Flutter renders at 124×92. */
function GraphSpot({ color }: { color: string }) {
  const cx = 56;
  const cy = 40;
  const hub = { x: cx - 2, y: cy + 2, r: 7 };
  const sats = [
    { x: cx - 36, y: cy - 22, r: 5 },
    { x: cx + 30, y: cy - 26, r: 5.5 },
    { x: cx + 40, y: cy + 16, r: 4.5 },
    { x: cx - 28, y: cy + 24, r: 5 },
  ];
  const fill = spotFill(color);
  return (
    <SpotSvg width={124} height={92} viewBox="0 0 112 80" color={color}>
      {sats.map((s, i) => (
        <line key={i} x1={hub.x} y1={hub.y} x2={s.x} y2={s.y} />
      ))}
      <line x1={sats[1].x} y1={sats[1].y} x2={sats[2].x} y2={sats[2].y} />
      {[hub, ...sats].map((b, i) => (
        <g key={i}>
          <circle cx={b.x} cy={b.y} r={b.r} fill={fill} stroke="none" />
          <circle cx={b.x} cy={b.y} r={b.r} />
        </g>
      ))}
    </SpotSvg>
  );
}

/* ------------------------------------------------------------------ */
/* Slides                                                              */
/* ------------------------------------------------------------------ */

const SPOT = 'rgba(150,168,133,0.75)';

function PageHook() {
  return (
    <div className="onboarding-page pad-wide">
      <div style={{ height: 24 }} />
      <span className="ob-pill">
        <LinkIcon size={16} />
        <span>ANY SOURCE · ANY FORMAT</span>
      </span>
      <div style={{ height: 32 }} />
      <h1 className="ob-headline lg">
        Any Link,
        <br />
        <span className="hl-accent">Captured.</span>
      </h1>
      <div style={{ height: 28 }} />
      <CaptureSpot color={SPOT} />
      <div style={{ height: 32 }} />
      <p className="ob-body lg">
        Videos, articles, newsletters, Wikipedia — paste any link and Cachy distills the key
        takeaways into a browsable card.
      </p>
    </div>
  );
}

const FEATURES = [
  {
    Icon: ListDashes,
    title: 'Exact Ingredients & Steps',
    subtitle: 'Extracted directly from on-screen text + voice',
  },
  {
    Icon: MapPin,
    title: 'Places & Coordinates',
    subtitle: 'Hidden cafes and travel spots mapped out',
  },
  {
    Icon: CheckCircle,
    title: 'Immediate To-Dos',
    subtitle: 'Export checklists straight to your routine',
  },
];

function PageStructure() {
  return (
    <div className="onboarding-page pad-narrow">
      <div style={{ height: 16 }} />
      <StructureSpot color={SPOT} />
      <div style={{ height: 24 }} />
      <h1 className="ob-headline sm">
        Every Source,
        <br />
        <span className="hl-accent">Structured.</span>
      </h1>
      <div style={{ height: 12 }} />
      <p className="ob-body md">
        Videos, articles, threads — any content becomes clean, scannable action cards.
      </p>
      <div style={{ height: 24 }} />
      <div className="ob-card">
        {FEATURES.map(({ Icon, title, subtitle }, i) => (
          <div key={title}>
            {i > 0 && <hr className="ob-divider" />}
            <div className="ob-feature-row">
              <span className="ob-feature-ico">
                <Icon size={20} />
              </span>
              <span>
                <span className="ob-feature-title">{title}</span>
                <div className="ob-feature-sub">{subtitle}</div>
              </span>
            </div>
          </div>
        ))}
        <div className="ob-tags">
          <span className="ob-tag active">4 prep steps</span>
          <span className="ob-tag">Kyoto Speakeasy</span>
          <span className="ob-tag">DIY Woodwork</span>
        </div>
      </div>
    </div>
  );
}

const VAULT_ROWS = [
  { title: 'Crispy Chili Oil Eggs', tag: 'Recipe', time: 'Today' },
  { title: 'Hidden Tokyo Speakeasy', tag: 'Travel', time: 'Yesterday' },
  { title: 'Zone 2 Cardio Protocols', tag: 'Fitness', time: '3d ago' },
];

function PageLibrary() {
  return (
    <div className="onboarding-page pad-narrow">
      <div style={{ height: 16 }} />
      <GraphSpot color={SPOT} />
      <div style={{ height: 24 }} />
      <h1 className="ob-headline sm">
        Personal Web
        <br />
        <span className="hl-accent">Of Action.</span>
      </h1>
      <div style={{ height: 12 }} />
      <p className="ob-body md">Everything you keep is searchable and linked forever.</p>
      <div style={{ height: 24 }} />
      <div className="ob-vault-card">
        <div className="ob-vault-head">
          <span className="ob-vault-title">My Cachy Vault</span>
          <span className="ob-vault-count">
            <Bookmark size={14} weight="fill" />
            18 cards
          </span>
        </div>
        {VAULT_ROWS.map((row) => (
          <div key={row.title}>
            <hr className="ob-divider" />
            <div className="ob-vault-row">
              <span>
                <div className="ob-vault-row-title">{row.title}</div>
                <div className="ob-vault-row-time">{row.time}</div>
              </span>
              <span className="ob-vault-tag">{row.tag}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Screen                                                              */
/* ------------------------------------------------------------------ */

/**
 * First-run walkthrough. `onDone` fires on Skip / Enter Cachy; the launch
 * gate (App.tsx) records that onboarding was seen and moves on to sign-in.
 */
export default function OnboardingScreen({ onDone }: { onDone: () => void }) {
  const [index, setIndex] = useState(0);
  const touchX = useRef<number | null>(null);
  const last = index === 2;

  const done = onDone;

  const onTouchStart = (e: React.TouchEvent) => {
    touchX.current = e.touches[0].clientX;
  };
  const onTouchEnd = (e: React.TouchEvent) => {
    if (touchX.current == null) return;
    const dx = e.changedTouches[0].clientX - touchX.current;
    touchX.current = null;
    if (dx < -60 && index < 2) setIndex(index + 1);
    else if (dx > 60 && index > 0) setIndex(index - 1);
  };

  return (
    <div className="onboarding-root">
      <div className="onboarding-topbar">
        <CachyWordmark size={20} />
        <button className="onboarding-skip" onClick={done}>
          Skip
        </button>
      </div>

      <div
        className="onboarding-viewport"
        onTouchStart={onTouchStart}
        onTouchEnd={onTouchEnd}
      >
        <div
          className="onboarding-track"
          style={{ transform: `translateX(-${index * 33.3333}%)` }}
        >
          <PageHook />
          <PageStructure />
          <PageLibrary />
        </div>
      </div>

      <div className="onboarding-bottom">
        <div className="ob-dots">
          {[0, 1, 2].map((i) => (
            <button
              key={i}
              className={`ob-dot${i === index ? ' active' : ''}`}
              onClick={() => setIndex(i)}
              aria-label={`Go to slide ${i + 1}`}
            />
          ))}
        </div>
        <button
          className="onboarding-cta"
          onClick={() => (last ? done() : setIndex(index + 1))}
        >
          {last ? (
            <>
              Enter Cachy
              <ArrowRight size={18} />
            </>
          ) : (
            'Continue'
          )}
        </button>
      </div>
    </div>
  );
}

export { CachyGlyphSvg };
