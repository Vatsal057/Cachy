/**
 * ReaderScreen — faithful port of Flutter's reader_screen.dart (_ReaderView).
 * Face header (260px hero), category bar, headline, read-time strip,
 * core-takeaway card, sectioned blocks, action items, source line.
 */
import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import {
  AppWindow,
  ArrowLeft,
  ArrowsOutSimple,
  BookOpen,
  Check,
  Circle,
  Clock,
  FilmSlate,
  Lightbulb,
  ListChecks,
  MapPin,
  Microphone,
  MusicNote,
  PencilSimple,
  Cube,
  Share,
  ShoppingBag,
  Television,
  X,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api, apiErrorMessage } from '../../api/client';
import { CardState } from '../../api/types';
import type { ActionItems, Card, CatalogEntry, ConceptEntry } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import { useToast } from '../../ui/feedback';
import BlockList from './BlockRenderer';
import PrimaryActionBar from './PrimaryActionBar';
import InsightSection, {
  hasInsightContent,
  parseInsight,
} from './InsightSection';
import { addHighlight } from './highlights';
import { openLookup } from './artifactLookup';
import ShareSheet from '../share/ShareSheet';
import './reader.css';

/* ------------------------------------------------------------------ */
/* Face header — 260px hero with gradient into the surface             */
/* ------------------------------------------------------------------ */

function FaceHeader({
  card,
  onBack,
  onShare,
}: {
  card: Card;
  onBack: () => void;
  onShare: () => void;
}) {
  const accent = contentAccent(card.base.content_type);
  // media.thumbnail is a full proxy path (/media/{card_id}/thumb.jpg) — never
  // rebuild it. resolveMedia joins it to the base URL and appends ?token= for
  // authed /media/ paths (a plain <img> can't send the Authorization header).
  const ref = card.media?.thumbnail ?? card.media?.keyframes?.[0] ?? '';
  const src = ref ? api.resolveMedia(ref) : null;
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [card.card_id, src]);

  return (
    <header className="face-header">
      {src && !failed ? (
        <img
          key={src}
          src={src}
          alt=""
          className="face-img"
          onError={() => setFailed(true)}
        />
      ) : (
        <div
          aria-hidden
          style={{
            position: 'absolute',
            inset: 0,
            background: `linear-gradient(to bottom right, ${accent.color}59, ${accent.color}1a)`,
          }}
        />
      )}
      <div className="face-scrim" aria-hidden />
      <div className="face-topbar">
        <button type="button" className="circle-btn" onClick={onBack} aria-label="Back">
          <ArrowLeft size={22} color="#fff" />
        </button>
        {card.state === CardState.READY && (
          <button type="button" className="circle-btn" onClick={onShare} aria-label="Share">
            <Share size={22} color="#fff" />
          </button>
        )}
      </div>
    </header>
  );
}

/* ------------------------------------------------------------------ */
/* Category bar — accent type pill + neutral tag pills                 */
/* ------------------------------------------------------------------ */

function CategoryBar({ card }: { card: Card }) {
  const accent = contentAccent(card.base.content_type);
  const tags = card.base.tags ?? [];
  return (
    <div className="category-bar">
      <span
        className="type-pill"
        style={{
          color: accent.color,
          backgroundColor: `${accent.color}1f`,
          borderColor: `${accent.color}59`,
        }}
      >
        <accent.Icon size={11} />
        {accent.label.toUpperCase()}
      </span>
      {tags.map((t) => (
        <span key={t} className="tag-pill">
          {t.toUpperCase()}
        </span>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Read-time strip                                                     */
/* ------------------------------------------------------------------ */

const WORD_SPLIT = /\s+/;

function estimateReadMinutes(card: Card): number {
  let words = 0;
  const add = (v: unknown) => {
    if (typeof v === 'string')
      words += v.split(WORD_SPLIT).filter((w) => w.length > 0).length;
  };
  add(card.base.tldr);
  for (const b of card.blocks ?? []) {
    const r = b as unknown as Record<string, unknown>;
    add(r.text);
    for (const it of (r.items as unknown[]) ?? []) {
      const m = it as Record<string, unknown> | null;
      add(m && typeof m === 'object' ? m.text : it);
    }
    for (const st of (r.steps as unknown[]) ?? []) {
      const m = st as Record<string, unknown> | null;
      add(m && typeof m === 'object' ? m.text : st);
    }
  }
  return Math.max(1, Math.ceil(words / 200));
}

/* ------------------------------------------------------------------ */
/* Building status strip (processing)                                  */
/* ------------------------------------------------------------------ */

function BuildingStatusStrip({ card }: { card: Card }) {
  const label =
    card.state === CardState.QUEUED ? 'Queued — waking the pipeline' : 'Structuring your card';
  return (
    <div
      style={{
        marginBottom: 16,
        padding: '12px 14px',
        borderRadius: 12,
        background: 'var(--raised)',
        border: '1px solid var(--hairline)',
      }}
      role="status"
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span
          className="spinner"
          style={{ width: 14, height: 14, borderWidth: 2 }}
          aria-hidden
        />
        <span
          style={{
            fontFamily: 'var(--font-mono)',
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: '0.08em',
          }}
        >
          {label}
        </span>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Action items — "Actions" eyebrow + count; unfollowed preview vs     */
/* followed interactive checklist                                      */
/* ------------------------------------------------------------------ */

function ActionItemsSection({
  card,
  onChange,
}: {
  card: Card;
  onChange: (c: Card) => void;
}) {
  const ai = card.action_items;
  const accent = contentAccent(card.base.content_type);
  const [busy, setBusy] = useState(false);
  if (!ai || ai.items.length === 0) return null;
  const followed = ai.followed === true;

  const patch = async (next: ActionItems) => {
    setBusy(true);
    try {
      const updated = await api.updateActionItems(card.card_id, next);
      onChange(updated);
    } catch {
      // Optimistic fallback: keep the local state so the UI doesn't jump.
      onChange({ ...card, action_items: next });
    } finally {
      setBusy(false);
    }
  };

  const toggleItem = (id: string) =>
    void patch({
      ...ai,
      items: ai.items.map((it) =>
        it.id === id ? { ...it, done: !it.done } : it,
      ),
    });

  const setFollowed = (v: boolean) => void patch({ ...ai, followed: v });

  return (
    <section className="actions-section" aria-label="Actions">
      <div className="actions-head">
        <span
          className="section-eyebrow"
          style={{ color: accent.color, marginBottom: 0 }}
        >
          <span>Actions</span>
        </span>
        <span className="actions-count" style={{ color: accent.color }}>
          {ai.items.length}
        </span>
      </div>

      {!followed ? (
        <>
          <div className="actions-preview-card">
            {ai.items.map((it) => (
              <div key={it.id} className="actions-preview-row">
                <Circle
                  size={6}
                  weight="fill"
                  className="actions-preview-dot"
                  color={accent.color}
                />
                <span>{it.text}</span>
              </div>
            ))}
          </div>
          <button
            type="button"
            className="btn-primary btn-block"
            style={{ background: accent.color, color: '#fff' }}
            disabled={busy}
            onClick={() => setFollowed(true)}
          >
            <ListChecks size={18} />
            Track in Actions
          </button>
        </>
      ) : (
        <>
          <ul className="block-checklist">
            {ai.items.map((it) => (
              <li key={it.id}>
                <button
                  type="button"
                  className={`checkbox${it.done ? ' checked' : ''}`}
                  onClick={() => toggleItem(it.id)}
                  disabled={busy}
                  aria-pressed={it.done}
                  aria-label={it.done ? 'Mark not done' : 'Mark done'}
                >
                  {it.done && <Check size={17} weight="bold" />}
                </button>
                <span className={`checklist-text${it.done ? ' done' : ''}`}>
                  {it.text}
                </span>
              </li>
            ))}
          </ul>
          <div style={{ marginTop: 10 }}>
            <button
              type="button"
              className="btn-ghost btn-block"
              disabled={busy}
              onClick={() => setFollowed(false)}
            >
              <Check size={18} />
              Following — remove from Actions
            </button>
          </div>
        </>
      )}
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Embedded header — desktop split-pane compact header (port of          */
/* Flutter's _EmbeddedHeader): X close button + accent icon + content    */
/* type label + expand button. Used instead of FaceHeader when embedded.  */
/* ------------------------------------------------------------------ */

function EmbeddedHeader({
  card,
  onClose,
  onToggleFullscreen,
}: {
  card: Card;
  onClose?: () => void;
  onToggleFullscreen?: () => void;
}) {
  const accent = contentAccent(card.base.content_type);
  return (
    <header className="embedded-header">
      <button
        type="button"
        className="icon-btn"
        onClick={onClose}
        aria-label="Close"
      >
        <X size={20} />
      </button>
      <span
        className="embedded-header-icon"
        style={{ color: accent.color }}
        aria-hidden
      >
        <accent.Icon size={15} />
      </span>
      <span className="embedded-header-label">
        {(card.base.content_type ?? '').toUpperCase()}
      </span>
      {onToggleFullscreen && (
        <button
          type="button"
          className="icon-btn"
          onClick={onToggleFullscreen}
          aria-label="Fullscreen"
        >
          <ArrowsOutSimple size={20} />
        </button>
      )}
    </header>
  );
}

/* ------------------------------------------------------------------ */
/* References strip — port of Flutter's _ReferencesStrip              */
/* ------------------------------------------------------------------ */

const ARTIFACT_ICONS: Record<string, Icon> = {
  book: BookOpen,
  movie: FilmSlate,
  tv_show: Television,
  podcast: Microphone,
  music: MusicNote,
  product: ShoppingBag,
  place: MapPin,
  app: AppWindow,
  other: Cube,
};

function ReferencesStrip({
  entries,
  accentColor,
  onOpenArtifact,
  onSaveArtifact,
}: {
  entries: CatalogEntry[];
  accentColor: string;
  onOpenArtifact: (entry: CatalogEntry) => void;
  onSaveArtifact: (entry: CatalogEntry) => void;
}) {
  if (entries.length === 0) return null;

  return (
    <section className="reader-references-strip" aria-label="References">
      <span className="section-eyebrow" style={{ color: accentColor }}>
        <span>References</span>
      </span>
      <div className="reader-references-carousel">
        {entries.map((entry) => {
          const IconComp = ARTIFACT_ICONS[entry.type] ?? Cube;
          return (
            <button
              key={entry.id}
              type="button"
              className="reader-reference-tile"
              onClick={() => onOpenArtifact(entry)}
              onContextMenu={(e) => {
                e.preventDefault();
                onSaveArtifact(entry);
              }}
              title={`${entry.title} (right-click to save to catalog)`}
            >
              <div className="reader-reference-thumb">
                {entry.thumbnail ? (
                  <img src={entry.thumbnail} alt={entry.title} loading="lazy" />
                ) : (
                  <IconComp size={28} color="var(--muted)" />
                )}
              </div>
              <span className="reader-reference-title">{entry.title}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Concepts strip — port of Flutter's _ConceptsStrip                  */
/* ------------------------------------------------------------------ */

function ConceptsStrip({
  entries,
  accentColor,
  onOpenConcept,
}: {
  entries: ConceptEntry[];
  accentColor: string;
  onOpenConcept: (entry: ConceptEntry) => void;
}) {
  if (entries.length === 0) return null;

  return (
    <section className="reader-concepts-strip" aria-label="Concepts">
      <span className="section-eyebrow" style={{ color: accentColor }}>
        <span>Concepts</span>
      </span>
      <div className="reader-concepts-wrap">
        {entries.map((entry) => {
          const isMultiReel = entry.source_card_ids.length > 1;
          return (
            <button
              key={entry.id}
              type="button"
              className={`reader-concept-chip${isMultiReel ? ' multi-reel' : ''}`}
              onClick={() => onOpenConcept(entry)}
            >
              <Lightbulb
                size={14}
                weight={isMultiReel ? 'fill' : 'regular'}
                color={isMultiReel ? accentColor : undefined}
              />
              <span>{entry.name}</span>
              {isMultiReel && (
                <span className="reader-concept-count">
                  {entry.source_card_ids.length}
                </span>
              )}
            </button>
          );
        })}
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* ReaderScreen                                                        */
/* ------------------------------------------------------------------ */

export interface ReaderScreenProps {
  /** Override the route param — used when embedded in the library split pane. */
  cardId?: string;
  /** True when rendered inline in the desktop split pane: compact header,
   *  no hero face, inline action bar. */
  embedded?: boolean;
  /** Clears the pane selection. Only used when embedded is true. */
  onClose?: () => void;
  /** Expands to fullscreen. Only used when embedded is true. */
  onToggleFullscreen?: () => void;
}

export default function ReaderScreen(props: ReaderScreenProps = {}) {
  const { id: routeId } = useParams<{ id: string }>();
  const id = props.cardId ?? routeId;
  const embedded = props.embedded ?? false;
  const navigate = useNavigate();
  const [card, setCard] = useState<Card | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [artifacts, setArtifacts] = useState<CatalogEntry[]>([]);
  const [concepts, setConcepts] = useState<ConceptEntry[]>([]);
  const [shareOpen, setShareOpen] = useState(false);
  const { showToast, toastNode } = useToast();

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setCard(null);
    setError(null);
    const decodedId = decodeURIComponent(id);
    (async () => {
      try {
        const c = await api.getCard(decodedId);
        if (!cancelled) setCard(c);
      } catch (err) {
        if (!cancelled) setError(apiErrorMessage(err));
      }
    })();
    api.cardArtifacts(decodedId).then((res) => {
      if (!cancelled) setArtifacts(res);
    }).catch(() => {
      if (!cancelled) setArtifacts([]);
    });
    api.cardConcepts(decodedId).then((res) => {
      if (!cancelled) setConcepts(res);
    }).catch(() => {
      if (!cancelled) setConcepts([]);
    });
    return () => {
      cancelled = true;
    };
  }, [id]);

  const handleSaveArtifact = async (entry: CatalogEntry) => {
    try {
      await api.saveCatalogEntry(entry.id);
      showToast(`Saved "${entry.title}" to catalog`);
      setArtifacts((prev) =>
        prev.map((a) => (a.id === entry.id ? { ...a, saved: true } : a)),
      );
    } catch {
      showToast("Couldn't save to catalog");
    }
  };

  const readMins = useMemo(() => (card ? estimateReadMinutes(card) : 1), [card]);

  // The backend serves `insight` on the card JSON (Flutter parses it), but
  // src/api/types.ts doesn't declare it — read defensively via parseInsight.
  const insight = useMemo(
    () =>
      card
        ? parseInsight((card as unknown as { insight?: unknown }).insight)
        : null,
    [card],
  );

  if (error) {
    return (
      <main className="page">
        <Link className="back-link" to="/">
          ← Library
        </Link>
        <div className="error-card" role="alert">
          <p className="title-md">Couldn&apos;t load this card</p>
          <p className="muted small">{error}</p>
        </div>
      </main>
    );
  }

  if (!card) {
    return (
      <main className="page">
        <div className="loading">
          <div className="spinner" aria-hidden />
          <p className="muted">Opening card…</p>
        </div>
      </main>
    );
  }

  const accent = contentAccent(card.base.content_type);
  const isProcessing =
    card.state === CardState.PROCESSING || card.state === CardState.QUEUED;
  const isReady = card.state === CardState.READY;
  const isFailed = card.state === CardState.FAILED;

  // Long-press → save highlight (port of Flutter reader_screen's onHighlight).
  // Local-only until the backend exposes highlight endpoints (see highlights.ts).
  const handleHighlight = (text: string) => {
    addHighlight({
      cardId: card.card_id,
      cardTitle: card.base.one_liner,
      text,
    });
    showToast('Saved to highlights');
  };

  return (
    <div className={`reader-page${embedded ? ' embedded' : ''}`}>
      {embedded ? (
        <EmbeddedHeader
          card={card}
          onClose={props.onClose}
          onToggleFullscreen={props.onToggleFullscreen}
        />
      ) : (
        <FaceHeader
          card={card}
          onBack={() => navigate(-1)}
          onShare={() => setShareOpen(true)}
        />
      )}

      <div className="reading-column">
        {isProcessing && <BuildingStatusStrip card={card} />}

        <CategoryBar card={card} />

        {card.base.one_liner ? (
          <h1 className="headline-lg">{card.base.one_liner}</h1>
        ) : null}

        <div className="meta-strip">
          <span className="read-time">
            <Clock size={11} />
            {readMins} min read
          </span>
        </div>

        {isFailed && (
          <div className="error-card" role="alert" style={{ marginBottom: 16 }}>
            <p className="title-md">Couldn&apos;t build this card</p>
            <p className="muted small">
              {card.failure_reason || 'The source may be unavailable.'}
            </p>
          </div>
        )}

        {card.base.tldr ? (
          <div className="takeaway">
            <span className="section-eyebrow" style={{ color: accent.color }}>
              <span>Core Takeaway</span>
            </span>
            <div className="takeaway-card">{card.base.tldr}</div>
          </div>
        ) : null}

        {isReady && card.blocks.length > 0 && (
          <>
            <div className="ornamental-divider" aria-hidden>
              <span style={{ color: accent.color }}>✦</span>
            </div>
            <p className="highlight-hint">
              <PencilSimple size={12} aria-hidden />
              Long-press any line to save it as a highlight.
            </p>
          </>
        )}

        <BlockList
          blocks={card.blocks ?? []}
          artifacts={artifacts}
          onOpenArtifact={openLookup}
          concepts={concepts}
          onOpenConcept={(c) => navigate(`/concepts/${encodeURIComponent(c.id)}`)}
          onHighlight={isReady ? handleHighlight : undefined}
          notify={showToast}
        />

        {isReady && (
          <ActionItemsSection card={card} onChange={setCard} />
        )}

        {isReady && hasInsightContent(insight) && insight && (
          <InsightSection
            insight={insight}
            accentColor={accent.color}
            readMinutes={readMins}
            notify={showToast}
          />
        )}

        {isReady && artifacts.length > 0 && (
          <ReferencesStrip
            entries={artifacts}
            accentColor={accent.color}
            onOpenArtifact={openLookup}
            onSaveArtifact={(entry) => void handleSaveArtifact(entry)}
          />
        )}

        {isReady && concepts.length > 0 && (
          <ConceptsStrip
            entries={concepts}
            accentColor={accent.color}
            onOpenConcept={(c) => navigate(`/concepts/${encodeURIComponent(c.id)}`)}
          />
        )}

        {card.source.creator && (
          <div className="reader-source">
            <span className="muted small">
              {[card.source.platform, card.source.creator]
                .filter(Boolean)
                .join(' · ')}
            </span>
            <a
              className="small"
              href={card.source.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              View original
            </a>
          </div>
        )}
      </div>

      <PrimaryActionBar card={card} notify={showToast} />

      {shareOpen && (
        <div className="sheet-backdrop" onClick={() => setShareOpen(false)}>
          <div className="sheet" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="Share card">
            <div className="sheet-handle" aria-hidden />
            <ShareSheet cardId={card.card_id} onClose={() => setShareOpen(false)} />
          </div>
        </div>
      )}

      {toastNode}
    </div>
  );
}
