/**
 * CardTile — faithful port of Flutter's card_tile.dart.
 * A content-visual face with a calm scrim carrying the one-liner,
 * meta pills, and a state badge. Tapping opens the reader.
 */
import './library.css';
import { memo, useEffect, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import { Check, Clock, Warning } from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api } from '../../api/client';
import { CardState } from '../../api/types';
import type { Block, Card, ChecklistBlock, StepListBlock } from '../../api/types';
import { contentAccent, failureLabel } from '../../ui/content-accent';

/** Append an alpha channel to a #RRGGBB hex color. */
function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(alpha * 255)
    .toString(16)
    .padStart(2, '0');
  return `${hex}${a}`;
}

/* ------------------------------------------------------------------ */
/* CardFace — thumbnail, or calm content-type accent panel on failure  */
/* ------------------------------------------------------------------ */

function AccentFace({ accentColor, Icon }: { accentColor: string; Icon: Icon }) {
  return (
    <div
      className="tile-accent-face"
      style={{
        background: `linear-gradient(to bottom right, ${withAlpha(accentColor, 0.35)}, ${withAlpha(accentColor, 0.1)})`,
      }}
      aria-hidden
    >
      <span className="bg-icon">
        <Icon size={120} color={accentColor} />
      </span>
      <span className="fg-icon">
        <Icon size={34} color={accentColor} />
      </span>
    </div>
  );
}

/**
 * `resolveMedia` on the api client resolves a media ref (absolute URL
 * passthrough; bare `/media/…` paths joined onto the base host with
 * `?token=` for the auth-gated proxy, mirroring Dart's `resolveMedia`).
 * Bound here so `this` stays attached when called as a plain function.
 */
const resolveMediaFn = api.resolveMedia.bind(api);

function CardFace({ card }: { card: Card }) {
  const accent = contentAccent(card.base.content_type);
  const ref = card.media?.thumbnail ?? card.media?.keyframes?.[0] ?? null;
  const [failed, setFailed] = useState(false);
  const src = ref && !failed && resolveMediaFn ? resolveMediaFn(ref) : null;
  // reset failed state when the card changes
  useEffect(() => { setFailed(false); }, [card.card_id, ref]);
  if (!src) return <AccentFace accentColor={accent.color} Icon={accent.Icon} />;
  return (
    <div className="tile-face">
      <img
        src={src}
        alt=""
        loading="lazy"
        decoding="async"
        onError={() => setFailed(true)}
        onLoad={(e) => e.currentTarget.classList.add('loaded')}
      />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* StateBadge — hidden when ready                                     */
/* ------------------------------------------------------------------ */

function StateBadge({ card }: { card: Card }) {
  if (card.state === CardState.READY) return null;
  return (
    <span className="state-badge" aria-label={card.state}>
      {card.state === CardState.QUEUED && (
        <>
          <Clock size={13} color="rgba(255,255,255,0.7)" />
          <span className="sb-label">Queued</span>
        </>
      )}
      {card.state === CardState.PROCESSING && (
        <>
          <span className="spinner" style={{ width: 11, height: 11, borderWidth: 1.8 }} aria-hidden />
          <span className="sb-label">Working</span>
        </>
      )}
      {card.state === CardState.FAILED && (
        <>
          <Warning size={13} color="#FF8A7A" />
          <span className="sb-label" style={{ color: '#FF8A7A' }}>
            {failureLabel(card.failure_reason)}
          </span>
        </>
      )}
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* MetaPills — actions / steps / Deep                                 */
/* ------------------------------------------------------------------ */

function stepCount(blocks: Block[]): number {
  let n = 0;
  for (const b of blocks) {
    if (b.type === 'step_list') {
      const steps = (b as StepListBlock).steps;
      if (Array.isArray(steps)) n += steps.length;
    }
    if (b.type === 'checklist') {
      const items = (b as ChecklistBlock).items;
      if (Array.isArray(items)) n += items.length;
    }
  }
  return n;
}

function hasInsight(card: Card): boolean {
  const insight = (card as unknown as { insight?: { hasContent?: boolean } }).insight;
  return !!insight?.hasContent;
}

function MetaPills({ card }: { card: Card }) {
  const actions = card.action_items?.items.length ?? 0;
  const steps = stepCount(card.blocks ?? []);
  const deep = hasInsight(card);
  if (actions === 0 && steps === 0 && !deep) return null;
  return (
    <div className="meta-pills">
      {actions > 0 && (
        <span className="meta-pill">
          {actions} {actions === 1 ? 'action' : 'actions'}
        </span>
      )}
      {steps > 0 && <span className="meta-pill">{steps} steps</span>}
      {deep && <span className="meta-pill highlight">Deep</span>}
    </div>
  );
}

import { ContextMenu, buildCardMenuActions } from '../../ui/context-menu';

/* ------------------------------------------------------------------ */
/* CardTile                                                           */
/* ------------------------------------------------------------------ */

export interface CardTileProps {
  card: Card;
  onTap: (e?: React.MouseEvent) => void;
  onDelete?: () => void;
  confirmTitle?: string;
  confirmBody?: string;
  confirmAction?: string;
  selected?: boolean;
  selectionActive?: boolean;
  onSelectToggle?: () => void;
  onRangeSelect?: () => void;
  onEnterSelectionMode?: () => void;
  onOpenInNewTab?: () => void;
}

function CardTile({
  card,
  onTap,
  onDelete,
  confirmTitle = 'Delete card?',
  confirmBody = 'This removes the card and its media.',
  confirmAction = 'Delete',
  selected = false,
  selectionActive = false,
  onSelectToggle,
  onRangeSelect,
  onEnterSelectionMode,
  onOpenInNewTab,
}: CardTileProps) {
  const accent = contentAccent(card.base.content_type);
  const title =
    card.base.one_liner ||
    (card.state === CardState.PROCESSING || card.state === CardState.QUEUED
      ? 'Working on it…'
      : 'Untitled');
  const tags = card.base.tags ?? [];
  const pressTimer = useRef<number | null>(null);
  const [menuPos, setMenuPos] = useState<{ x: number; y: number } | null>(null);

  const confirmDelete = () => {
    if (!onDelete) return;
    if (window.confirm(`${confirmTitle}\n\n${confirmBody}\n\nOK = ${confirmAction}`)) {
      onDelete();
    }
  };

  const clearPressTimer = () => {
    if (pressTimer.current !== null) {
      window.clearTimeout(pressTimer.current);
      pressTimer.current = null;
    }
  };

  const handleClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.shiftKey && onRangeSelect) {
      e.preventDefault();
      onRangeSelect();
      return;
    }
    if ((e.metaKey || e.ctrlKey) && onSelectToggle) {
      e.preventDefault();
      onSelectToggle();
      return;
    }
    if (selectionActive && onSelectToggle) {
      e.preventDefault();
      onSelectToggle();
      return;
    }
    onTap(e);
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      if (selectionActive && onSelectToggle) {
        onSelectToggle();
      } else {
        onTap();
      }
    }
  };

  return (
    <>
      <div
        className={`card-tile${selected ? ' selected' : ''}`}
        role="button"
        tabIndex={0}
        aria-label={title}
        aria-selected={selected}
        onClick={handleClick}
        onKeyDown={handleKeyDown}
        onContextMenu={(e) => {
          e.preventDefault();
          setMenuPos({ x: e.clientX, y: e.clientY });
        }}
        onPointerDown={() => {
          clearPressTimer();
          pressTimer.current = window.setTimeout(() => {
            if (onEnterSelectionMode) {
              onEnterSelectionMode();
            } else if (onDelete) {
              confirmDelete();
            }
          }, 550);
        }}
        onPointerUp={clearPressTimer}
        onPointerLeave={clearPressTimer}
        onPointerMove={clearPressTimer}
        style={{ '--tile-accent': accent.color } as React.CSSProperties}
      >
        <CardFace card={card} />
        <div className="tile-scrim" aria-hidden />
        <div className="tile-content">
          <div className="tile-type-row">
            <accent.Icon size={13} color="rgba(255,255,255,0.7)" />
            <span className="tile-type-label">{accent.label.toUpperCase()}</span>
            {tags.length > 0 && <span className="tile-tag-pill">{tags[0]}</span>}
          </div>
          <p className="tile-title">{title}</p>
          {card.state === CardState.READY && <MetaPills card={card} />}
        </div>
        <StateBadge card={card} />

        {selected && (
          <>
            <div className="tile-selection-overlay" aria-hidden />
            <div className="tile-selection-badge" aria-hidden>
              <Check size={14} weight="bold" />
            </div>
          </>
        )}
      </div>

      {menuPos && (
        <ContextMenu
          x={menuPos.x}
          y={menuPos.y}
          actions={buildCardMenuActions({
            isDesktopPlatform: true,
            onOpen: () => onTap(),
            onOpenNewTab: () => {
              if (onOpenInNewTab) {
                onOpenInNewTab();
              } else {
                window.open(`/reader/${encodeURIComponent(card.card_id)}`, '_blank');
              }
            },
            onCopyLink: async () => {
              const url = card.source?.url;
              if (url) {
                await navigator.clipboard.writeText(url).catch(() => {});
              }
            },
            onDelete: () => {
              confirmDelete();
            },
          })}
          onClose={() => setMenuPos(null)}
        />
      )}
    </>
  );
}

/**
 * Custom memo comparison. The tile's rendered surface depends on the card's
 * volatile fields plus its selection state.
 */
function cardTilePropsEqual(prev: CardTileProps, next: CardTileProps): boolean {
  if (prev.selected !== next.selected) return false;
  if (prev.selectionActive !== next.selectionActive) return false;
  const a = prev.card;
  const b = next.card;
  if (a === b) return true;
  return (
    a.card_id === b.card_id &&
    a.state === b.state &&
    (a.failure_reason ?? null) === (b.failure_reason ?? null) &&
    (a.media?.thumbnail ?? null) === (b.media?.thumbnail ?? null) &&
    (a.media?.keyframes?.[0] ?? null) === (b.media?.keyframes?.[0] ?? null) &&
    a.base.one_liner === b.base.one_liner &&
    a.base.content_type === b.base.content_type &&
    (a.base.tags?.[0] ?? null) === (b.base.tags?.[0] ?? null) &&
    (a.action_items?.items.length ?? 0) === (b.action_items?.items.length ?? 0) &&
    stepCount(a.blocks ?? []) === stepCount(b.blocks ?? []) &&
    hasInsight(a) === hasInsight(b)
  );
}

export default memo(CardTile, cardTilePropsEqual);

/** Check icon re-export for the selection overlay. */
export { Check };

