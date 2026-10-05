/**
 * LibraryScreen — faithful port of Flutter's library_screen.dart.
 * Wordmark header, animated CARDS/CONCEPTS/CATALOG tabs (sliding pill +
 * cross-fading panels, mirroring Flutter's TabBar/TabBarView), tag filter
 * bar, card grid (2–8 columns from available width), CTA tile at the end.
 *
 * All three tab panels stay mounted — switching tabs cross-fades the
 * content (180ms ease-out) with a slight directional slide while the pill
 * indicator glides between positions. Horizontal swipes on the content
 * area also switch tabs. Tab selection is internal state; the
 * /concepts and /catalog routes render this screen with the matching
 * initial tab so deep links still land on the right section.
 *
 * Cards load PAGE_SIZE at a time with infinite scroll (IntersectionObserver
 * on a sentinel div at the end of the grid). Tag/collection filters reset
 * pagination; the collection filter is server-side, the tag filter applies
 * client-side over the loaded pages.
 */
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
  type TouchEvent,
} from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { BookOpen, Chats, Graph, MagnifyingGlass, Plus } from 'phosphor-react';
import { api, apiErrorMessage } from '../../api/client';
import type { Card } from '../../api/types';
import { useAuth } from '../auth/AuthContext';
import { useMedia } from '../../ui/use-media';
import ConceptsScreen from '../concepts/ConceptsScreen';
import CatalogScreen from '../catalog/CatalogScreen';
import ReaderScreen from '../reader/ReaderScreen';
import CardTile from './CardTile';
import './library.css';

/* ------------------------------------------------------------------ */
/* Cachy wordmark — U-bracket glyph cradling a reel square (SVG port   */
/* of Flutter's CachyGlyph painter) + "cachy" in Fraunces.             */
/* ------------------------------------------------------------------ */

function CachyGlyph({ size = 26 }: { size?: number }) {
  const w = 28;
  const h = 28;
  const stroke = w * 0.13;
  return (
    <svg
      width={size * 1.08}
      height={size * 1.08}
      viewBox={`0 0 ${w} ${h}`}
      aria-hidden
    >
      <path
        d={`M ${w * 0.18} ${h * 0.3} L ${w * 0.18} ${h * 0.66}
            A ${w * 0.16} ${w * 0.16} 0 0 0 ${w * 0.34} ${h * 0.82}
            L ${w * 0.66} ${h * 0.82}
            A ${w * 0.16} ${w * 0.16} 0 0 0 ${w * 0.82} ${h * 0.66}
            L ${w * 0.82} ${h * 0.3}`}
        fill="none"
        stroke="var(--accent)"
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect
        x={w * 0.5 - (w * 0.3) / 2}
        y={h * 0.5 - (w * 0.3) / 2}
        width={w * 0.3}
        height={w * 0.3}
        rx={w * 0.3 * 0.32}
        fill="var(--accent)"
        opacity={0.5}
      />
    </svg>
  );
}

function Wordmark() {
  return (
    <Link to="/" className="wordmark" aria-label="Cachy home">
      <CachyGlyph size={24} />
      <span className="wordmark-text">cachy</span>
    </Link>
  );
}

/* ------------------------------------------------------------------ */
/* Animated segmented tabs — CARDS / CONCEPTS / CATALOG                 */
/* ------------------------------------------------------------------ */

export type LibraryTab = 'cards' | 'concepts' | 'catalog';

const TABS: { id: LibraryTab; label: string }[] = [
  { id: 'cards', label: 'CARDS' },
  { id: 'concepts', label: 'CONCEPTS' },
  { id: 'catalog', label: 'CATALOG' },
];

function tabIndex(t: LibraryTab): number {
  return TABS.findIndex((x) => x.id === t);
}

/**
 * Segmented control with a sliding pill indicator (Flutter TabBar port:
 * 40px container, 12px radius, surface-highest @ 0.6; pill radius 10 with
 * shadow on 3px padding; mono 12px labels, w700 active / w500 inactive).
 * The pill's position is driven by `--lib-idx` and glides via a 180ms
 * ease-out transform transition — no animation library needed.
 */
function SegmentedTabs({
  active,
  onChange,
}: {
  active: LibraryTab;
  onChange: (t: LibraryTab) => void;
}) {
  return (
    <div
      className="lib-tabs"
      role="tablist"
      aria-label="Library sections"
      style={{ '--lib-idx': tabIndex(active) } as CSSProperties}
    >
      <span className="lib-tabs-indicator" aria-hidden />
      {TABS.map((t) => (
        <button
          key={t.id}
          id={`lib-tab-${t.id}`}
          role="tab"
          aria-selected={t.id === active}
          aria-controls={`lib-panel-${t.id}`}
          className={`lib-tab${t.id === active ? ' active' : ''}`}
          onClick={() => onChange(t.id)}
          type="button"
        >
          {t.label}
        </button>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* CTA card — "Capture another reel"                                   */
/* ------------------------------------------------------------------ */

function CtaCard() {
  const navigate = useNavigate();
  return (
    <button
      type="button"
      className="cta-card"
      onClick={() => navigate('/capture')}
      aria-label="Capture another reel"
    >
      <span className="cta-circle">
        <Plus size={20} />
      </span>
      <span className="cta-label">{'Capture\nanother reel'}</span>
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* SplitPane — master-detail layout (port of Flutter's split_pane.dart). */
/* List panel: fraction of width, clamped [280px, 50%]. Draggable        */
/* divider. Detail panel fills the remainder.                            */
/* ------------------------------------------------------------------ */

function resolveSplitListWidth(availableWidth: number, fraction: number) {
  return Math.min(
    Math.max(availableWidth * fraction, 280),
    availableWidth * 0.5,
  );
}

function SplitPane({
  list,
  detail,
  fraction,
  onFractionChanged,
}: {
  list: ReactNode;
  detail: ReactNode;
  fraction: number;
  onFractionChanged: (f: number) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [listWidth, setListWidth] = useState<number | null>(null);
  const draggingRef = useRef(false);

  const availableWidth = containerRef.current?.clientWidth ?? 0;
  const width = listWidth ?? resolveSplitListWidth(availableWidth || 1200, fraction);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setListWidth(null));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const handlePointerDown = useCallback((e: ReactPointerEvent) => {
    draggingRef.current = true;
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  }, []);

  const handlePointerMove = useCallback(
    (e: ReactPointerEvent) => {
      if (!draggingRef.current) return;
      const el = containerRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const availableWidth = rect.width;
      const newWidth = Math.min(
        Math.max(e.clientX - rect.left, 280),
        availableWidth * 0.5,
      );
      setListWidth(newWidth);
    },
    [],
  );

  const handlePointerUp = useCallback(() => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    const el = containerRef.current;
    if (!el || listWidth === null) return;
    const availableWidth = el.clientWidth;
    if (availableWidth > 0) {
      onFractionChanged(listWidth / availableWidth);
    }
  }, [listWidth, onFractionChanged]);

  return (
    <div ref={containerRef} className="lib-split">
      <div className="lib-split-list" style={{ width }}>
        {list}
      </div>
      <div
        className="lib-split-divider"
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize panels"
      >
        <div className="lib-split-divider-line" aria-hidden />
      </div>
      <div className="lib-split-detail">
        {detail}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* ReaderPaneEmpty — shown when no card is selected in split-pane mode. */
/* Port of Flutter's _ReaderPaneEmpty.                                 */
/* ------------------------------------------------------------------ */

function ReaderPaneEmpty() {
  return (
    <div className="reader-pane-empty">
      <BookOpen size={36} className="reader-pane-empty-icon" aria-hidden />
      <p className="reader-pane-empty-label">Select a card to read</p>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* LibraryScreen                                                       */
/* ------------------------------------------------------------------ */

/** Cards per page — backend caps limit at 200, so 20 is comfortably inside. */
const PAGE_SIZE = 20;
/** Skeleton tiles shown while the first page or an appended page loads. */
const SKELETON_COUNT = 6;
/** Horizontal swipe distance that flips tabs. */
const SWIPE_THRESHOLD = 64;

export default function LibraryScreen({
  initialTab = 'cards',
}: {
  initialTab?: LibraryTab;
}) {
  const { logout } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const collectionId = searchParams.get('collection');

  /* ---- tab state ------------------------------------------------ */
  const [tab, setTab] = useState<LibraryTab>(initialTab);
  /** Slide direction of the last tab change: 1 = forward, -1 = back. */
  const [dir, setDir] = useState(1);
  const tabRef = useRef(tab);
  const initialTabRef = useRef(initialTab);

  /* ---- desktop split-pane (master-detail) ------------------------
     Port of Flutter's Insets.splitPane (1100px): at/above this width the
     cards tab shows a list+detail split pane. Tapping a card selects it
     into the side panel instead of navigating to /reader/:id. */
  const isSplitPane = useMedia('(min-width: 1100px)');
  const [selectedCardId, setSelectedCardId] = useState<string | null>(null);
  /** Split-pane list fraction — persisted to localStorage like Flutter's AppController. */
  const [splitFraction, setSplitFraction] = useState<number>(() => {
    try {
      const v = parseFloat(localStorage.getItem('cachy:splitPaneFraction') ?? '');
      return Number.isFinite(v) && v > 0 && v < 1 ? v : 0.42;
    } catch {
      return 0.42;
    }
  });

  const handleSplitFraction = useCallback((f: number) => {
    setSplitFraction(f);
    try {
      localStorage.setItem('cachy:splitPaneFraction', String(f));
    } catch {
      /* ignore */
    }
  }, []);

  /** Card tap: split-pane selects into the side panel, otherwise navigate. */
  const handleCardTap = useCallback(
    (card: Card) => {
      if (isSplitPane && tabRef.current === 'cards') {
        setSelectedCardId(card.card_id);
        return;
      }
      navigate(`/reader/${encodeURIComponent(card.card_id)}`);
    },
    [isSplitPane, navigate],
  );

  const selectTab = useCallback((next: LibraryTab) => {
    const cur = tabRef.current;
    if (cur === next) return;
    setDir(tabIndex(next) > tabIndex(cur) ? 1 : -1);
    tabRef.current = next;
    setTab(next);
  }, []);

  // The /concepts and /catalog routes render this screen with a different
  // initial tab. React Router updates (not remounts) the component when the
  // route changes, so sync the tab — the pill and panels animate to it.
  useEffect(() => {
    if (initialTab !== initialTabRef.current) {
      initialTabRef.current = initialTab;
      selectTab(initialTab);
    }
  }, [initialTab, selectTab]);

  /* ---- swipe to switch tabs ------------------------------------- */
  const touchStart = useRef<{ x: number; y: number } | null>(null);
  const handleTouchStart = useCallback((e: TouchEvent<HTMLDivElement>) => {
    const t = e.touches[0];
    touchStart.current = { x: t.clientX, y: t.clientY };
  }, []);
  const handleTouchEnd = useCallback(
    (e: TouchEvent<HTMLDivElement>) => {
      const s = touchStart.current;
      touchStart.current = null;
      if (!s) return;
      const t = e.changedTouches[0];
      const dx = t.clientX - s.x;
      const dy = t.clientY - s.y;
      // Vertical scrolls win — only deliberate horizontal swipes flip tabs.
      if (Math.abs(dx) < SWIPE_THRESHOLD || Math.abs(dx) < Math.abs(dy) * 1.4)
        return;
      const i = tabIndex(tab);
      if (dx < 0 && i < TABS.length - 1) selectTab(TABS[i + 1].id);
      else if (dx > 0 && i > 0) selectTab(TABS[i - 1].id);
    },
    [tab, selectTab],
  );

  /* ---- cards data (unchanged) ------------------------------------ */
  const [cards, setCards] = useState<Card[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tagFilter, setTagFilter] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const gridRef = useRef<HTMLDivElement>(null);
  const sentinelRef = useRef<HTMLDivElement>(null);
  const [cols, setCols] = useState(2);
  /** Next offset to fetch — a ref so the scroll observer never goes stale. */
  const offsetRef = useRef(0);
  /** Guards overlapping page fetches. */
  const loadingRef = useRef(false);
  /** Bumped on every first-page load; stale in-flight pages check it before writing state. */
  const seqRef = useRef(0);

  const pageParams = useCallback(
    (offset: number) => ({
      limit: PAGE_SIZE,
      offset,
      ...(collectionId ? { collection_id: collectionId } : {}),
    }),
    [collectionId],
  );

  /** First page — also the retry path and the filter-change reset. */
  const loadFirstPage = useCallback(async () => {
    const seq = ++seqRef.current;
    setError(null);
    setCards(null);
    setTagFilter(null);
    setHasMore(true);
    setLoadingMore(false);
    loadingRef.current = false;
    offsetRef.current = 0;
    try {
      const list = await api.listCards(pageParams(0));
      if (seqRef.current !== seq) return; // superseded by a newer filter
      offsetRef.current = list.length;
      setCards(list);
      // A short page means the backend has nothing more to give.
      setHasMore(list.length === PAGE_SIZE);
    } catch (err) {
      if (seqRef.current !== seq) return;
      setError(apiErrorMessage(err));
    }
  }, [pageParams]);

  useEffect(() => {
    void loadFirstPage();
  }, [loadFirstPage]);

  /** Append the next page; guarded against overlap, over-fetch, and filter changes mid-flight. */
  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMore) return;
    const seq = seqRef.current;
    const offset = offsetRef.current;
    loadingRef.current = true;
    setLoadingMore(true);
    try {
      const list = await api.listCards(pageParams(offset));
      if (seqRef.current !== seq) return; // filter changed mid-fetch
      offsetRef.current = offset + list.length;
      setCards((prev) => [...(prev ?? []), ...list]);
      setHasMore(list.length === PAGE_SIZE);
    } catch (err) {
      if (seqRef.current !== seq) return;
      setError(apiErrorMessage(err));
    } finally {
      // A newer first-page load already reset these; don't clobber it.
      if (seqRef.current === seq) {
        loadingRef.current = false;
        setLoadingMore(false);
      }
    }
  }, [pageParams, hasMore]);

  // Infinite scroll — the sentinel at the end of the grid fires ~600px
  // before it scrolls into view so the next page is ready in time.
  useEffect(() => {
    const el = sentinelRef.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) void loadMore();
      },
      { rootMargin: '600px' },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [loadMore]);

  // Columns from available width: floor(width / 200), clamped 2..8.
  useEffect(() => {
    const el = gridRef.current;
    if (!el) return;
    const compute = () => {
      const w = el.clientWidth;
      setCols(Math.min(8, Math.max(2, Math.floor(w / 200))));
    };
    compute();
    const ro = new ResizeObserver(compute);
    ro.observe(el);
    return () => ro.disconnect();
  }, [cards !== null]);

  const availableTags = useMemo(() => {
    const set = new Set<string>();
    for (const c of cards ?? []) {
      for (const t of c.base.tags ?? []) set.add(t);
    }
    return [...set].sort();
  }, [cards]);

  const visible = useMemo(() => {
    if (!cards) return [];
    if (!tagFilter) return cards;
    return cards.filter((c) => (c.base.tags ?? []).includes(tagFilter));
  }, [cards, tagFilter]);

  const handleDelete = async (card: Card) => {
    try {
      await api.deleteCard(card.card_id);
      // Keep the next page's offset aligned with the shrunken list.
      offsetRef.current = Math.max(0, offsetRef.current - 1);
      setCards((prev) => (prev ? prev.filter((c) => c.card_id !== card.card_id) : prev));
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const panelClass = (t: LibraryTab) =>
    `lib-panel${tab === t ? ' active' : ''}`;

  /* ---- cards panel content (extracted for split-pane reuse) -------- */
  const cardsContent = (
    <>
      {collectionId && (
        <p className="muted small">
          Filtered by collection ·{' '}
          <Link className="btn-link" to="/">
            Clear
          </Link>
        </p>
      )}

      {availableTags.length > 0 && (
        <div className="tagbar" role="toolbar" aria-label="Filter by tag">
          {availableTags.map((tag) => (
            <button
              key={tag}
              type="button"
              className={`chip${tagFilter === tag ? ' active' : ''}`}
              onClick={() => setTagFilter((cur) => (cur === tag ? null : tag))}
            >
              {tag.toUpperCase()}
            </button>
          ))}
        </div>
      )}

      {error && (
        <div className="error-card" role="alert">
          <p className="title-md">Can&apos;t reach Cachy</p>
          <p className="muted small">{error}</p>
          <div>
            <button className="btn-ghost btn-sm" onClick={() => void loadFirstPage()} type="button">
              Retry
            </button>
          </div>
        </div>
      )}

      {cards === null && !error ? (
        <div
          className="card-grid"
          ref={gridRef}
          style={{ gridTemplateColumns: `repeat(${cols}, 1fr)` }}
          aria-label="Loading"
        >
          {Array.from({ length: SKELETON_COUNT }).map((_, i) => (
            <div key={i} className="tile-skeleton" />
          ))}
        </div>
      ) : cards && cards.length === 0 ? (
        <div className="empty">
          <p className="display-sm">Your shelf is empty</p>
          <p className="muted">
            Share a reel to Cachy — or paste a link — and watch it become a card
            you can actually use.
          </p>
          <Link className="btn" to="/capture">
            Capture your first reel
          </Link>
        </div>
      ) : visible.length === 0 && !hasMore ? (
        <div className="empty">
          <p className="display-sm">Nothing here</p>
          <p className="muted">
            {tagFilter ? `No cards tagged "${tagFilter}".` : 'No cards match this filter.'}
          </p>
        </div>
      ) : (
        <div
          className="card-grid"
          ref={gridRef}
          style={{ gridTemplateColumns: `repeat(${cols}, 1fr)` }}
        >
          {visible.map((card) => (
            <CardTile
              key={card.card_id}
              card={card}
              onTap={() => handleCardTap(card)}
              onDelete={() => void handleDelete(card)}
            />
          ))}
          <CtaCard />
          {loadingMore &&
            Array.from({ length: SKELETON_COUNT }).map((_, i) => (
              <div key={`more-${i}`} className="tile-skeleton" aria-hidden />
            ))}
          {hasMore && !error && (
            <div ref={sentinelRef} style={{ height: 1 }} aria-hidden />
          )}
        </div>
      )}
    </>
  );

  /* ---- reader side panel (desktop split-pane detail) --------------- */
  const readerDetail = selectedCardId ? (
    <ReaderScreen
      key={selectedCardId}
      cardId={selectedCardId}
      embedded
      onClose={() => setSelectedCardId(null)}
      onToggleFullscreen={() =>
        navigate(`/reader/${encodeURIComponent(selectedCardId)}`)
      }
    />
  ) : (
    <ReaderPaneEmpty />
  );

  return (
    <main className="page">
      <div className="library-head">
        <Wordmark />
        <div className="library-actions">
          <button
            type="button"
            className="icon-btn"
            aria-label="Graph"
            onClick={() => navigate('/graph')}
          >
            <Graph size={22} />
          </button>
          <button
            type="button"
            className="icon-btn"
            aria-label="Chat"
            onClick={() => navigate('/feed')}
          >
            <Chats size={22} />
          </button>
          <button
            type="button"
            className="icon-btn"
            aria-label="Search"
            onClick={() => navigate('/search')}
          >
            <MagnifyingGlass size={22} />
          </button>
          <button type="button" className="btn-ghost btn-sm" onClick={logout}>
            Sign out
          </button>
        </div>
      </div>

      <SegmentedTabs active={tab} onChange={selectTab} />

      <div
        className="lib-panels"
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
        style={{ '--lib-dir': dir } as CSSProperties}
      >
        <section
          id="lib-panel-cards"
          role="tabpanel"
          aria-labelledby="lib-tab-cards"
          aria-hidden={tab !== 'cards'}
          className={panelClass('cards')}
        >
          {isSplitPane ? (
            <SplitPane
              list={cardsContent}
              detail={readerDetail}
              fraction={splitFraction}
              onFractionChanged={handleSplitFraction}
            />
          ) : (
            cardsContent
          )}
        </section>

        <section
          id="lib-panel-concepts"
          role="tabpanel"
          aria-labelledby="lib-tab-concepts"
          aria-hidden={tab !== 'concepts'}
          className={panelClass('concepts')}
        >
          <ConceptsScreen />
        </section>

        <section
          id="lib-panel-catalog"
          role="tabpanel"
          aria-labelledby="lib-tab-catalog"
          aria-hidden={tab !== 'catalog'}
          className={panelClass('catalog')}
        >
          <CatalogScreen />
        </section>
      </div>
    </main>
  );
}
