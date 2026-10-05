import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  AppWindow,
  ArrowClockwise,
  ArrowUpRight,
  Article,
  BookOpen,
  CaretLeft,
  CaretRight,
  FilmSlate,
  MapPin,
  Microphone,
  MusicNote,
  Cube,
  ShoppingBag,
  Sparkle,
  Television,
  WifiX,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import './catalog.css';

// The catalog — mirrors Flutter's catalog_screen.dart + catalog_detail_screen:
// a browsable wall of artifact covers grouped by type, typed placeholders,
// long-press to delete, and a full detail page (not a modal) with Fetch info,
// Search the web, Appears in, and Related.

interface CatalogEntryView {
  id: string;
  type: string;
  title: string;
  creator?: string | null;
  year?: number | null;
  thumbnail?: string | null;
  description?: string | null;
  source_card_ids: string[];
}

function normalize(raw: any): CatalogEntryView {
  return {
    id: String(raw.id ?? raw.artifact_id ?? ''),
    type: String(raw.type ?? 'other'),
    title: String(raw.title ?? 'Untitled'),
    creator: (raw.creator as string | null | undefined) ?? null,
    year: typeof raw.year === 'number' ? raw.year : null,
    thumbnail: (raw.thumbnail as string | null | undefined) ?? null,
    description: (raw.description as string | null | undefined) ?? null,
    source_card_ids: Array.isArray(raw.source_card_ids)
      ? raw.source_card_ids.map(String)
      : [],
  };
}

// Plural section labels — mirrors ArtifactType.sectionLabel.
const TYPE_ORDER = [
  'book',
  'movie',
  'tv_show',
  'podcast',
  'music',
  'product',
  'place',
  'app',
  'other',
];

const TYPE_LABEL: Record<string, string> = {
  book: 'Books',
  movie: 'Movies',
  tv_show: 'TV Shows',
  podcast: 'Podcasts',
  music: 'Music',
  product: 'Products',
  place: 'Places',
  app: 'Apps',
  other: 'Other',
};

const TYPE_ICON: Record<string, Icon> = {
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

function typeLabel(t: string): string {
  return TYPE_LABEL[t] ?? t;
}

function typeIcon(t: string): Icon {
  return TYPE_ICON[t] ?? Cube;
}

function subtitleOf(e: CatalogEntryView): string {
  const parts: string[] = [];
  if (e.creator) parts.push(e.creator);
  if (e.year != null) parts.push(String(e.year));
  return parts.join(' · ');
}

// Product/artifact lookup — mirrors artifact_lookup.dart lookupUri.
function lookupUrl(e: CatalogEntryView): string {
  const q = [e.title, e.creator ?? ''].filter((s) => s.trim()).join(' ');
  const query = encodeURIComponent(q || e.title);
  switch (e.type) {
    case 'product':
      return `https://www.google.com/search?tbm=shop&q=${query}`;
    case 'book':
      return `https://www.google.com/search?tbm=bks&q=${query}`;
    case 'movie':
    case 'tv_show':
      return `https://www.imdb.com/find/?q=${query}`;
    case 'podcast':
    case 'music':
      return `https://music.apple.com/search?term=${query}`;
    case 'place':
      return `https://www.google.com/maps/search/?api=1&query=${query}`;
    default:
      return `https://www.google.com/search?q=${query}`;
  }
}

// Spot illustration — transcribes Flutter's CatalogSpot painter.
function CatalogSpotArt() {
  const c = 'var(--ink-muted)';
  return (
    <svg width={112} height={74} viewBox="0 0 112 74" aria-hidden>
      <g
        stroke={c}
        strokeOpacity={0.55}
        strokeWidth={1.7}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      >
        <g transform="translate(26 37) rotate(-5.73)">
          <rect x={-18} y={-26} width={36} height={52} rx={4} />
          <line x1={-10} y1={-26} x2={-10} y2={26} />
        </g>
        <g transform="translate(82 39) rotate(4.58)">
          <rect x={-22} y={-20} width={44} height={40} rx={4} />
          {[-22, 22].map((x) =>
            [0, 1, 2].map((i) => {
              const y = -14 + i * 12;
              return (
                <line key={`${x}-${i}`} x1={x - 3} y1={y} x2={x + 3} y2={y} />
              );
            }),
          )}
        </g>
      </g>
    </svg>
  );
}

function Cover({
  entry,
  iconSize = 32,
}: {
  entry: CatalogEntryView;
  iconSize?: number;
}) {
  const [failed, setFailed] = useState(false);
  const Icon = typeIcon(entry.type);
  if (!entry.thumbnail || failed) {
    return (
      <span className="ct-cover-ph">
        <Icon size={iconSize} />
      </span>
    );
  }
  return (
    <img
      src={entry.thumbnail}
      alt=""
      loading="lazy"
      onError={() => setFailed(true)}
    />
  );
}

function useLongPress(onLongPress: () => void, ms = 550) {
  const timer = useRef<number | null>(null);
  const fired = useRef(false);
  const cancel = useCallback(() => {
    if (timer.current !== null) {
      window.clearTimeout(timer.current);
      timer.current = null;
    }
  }, []);
  return {
    onPointerDown: () => {
      fired.current = false;
      cancel();
      timer.current = window.setTimeout(() => {
        fired.current = true;
        onLongPress();
      }, ms);
    },
    onPointerUp: cancel,
    onPointerLeave: cancel,
    onPointerMove: cancel,
    onContextMenu: (e: React.SyntheticEvent) => {
      e.preventDefault();
      if (!fired.current) onLongPress();
    },
  };
}

function ConfirmDialog({
  title,
  message,
  onCancel,
  onConfirm,
}: {
  title: string;
  message: string;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="ct-dialog-backdrop" onClick={onCancel}>
      <div
        className="ct-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
      >
        <h3>{title}</h3>
        <p>{message}</p>
        <div className="ct-dialog-actions">
          <button className="ct-dialog-cancel" onClick={onCancel}>
            Cancel
          </button>
          <button className="ct-dialog-remove" onClick={onConfirm}>
            Remove
          </button>
        </div>
      </div>
    </div>
  );
}

function ArtifactTile({
  entry,
  onOpen,
  onDelete,
}: {
  entry: CatalogEntryView;
  onOpen: () => void;
  onDelete: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const lp = useLongPress(() => setConfirming(true));
  const sub = subtitleOf(entry);
  return (
    <>
      <button className="ct-tile" onClick={onOpen} {...lp}>
        <span className="ct-cover">
          <Cover entry={entry} />
        </span>
        <span className="ct-title">{entry.title}</span>
        {sub ? <span className="ct-subtitle">{sub}</span> : null}
      </button>
      {confirming ? (
        <ConfirmDialog
          title="Remove from catalog?"
          message={`“${entry.title}” will be removed from the catalog.`}
          onCancel={() => setConfirming(false)}
          onConfirm={() => {
            setConfirming(false);
            onDelete();
          }}
        />
      ) : null}
    </>
  );
}

// ---------------------------------------------------------------------------
// Detail page
// ---------------------------------------------------------------------------

function CatalogDetail({
  entry,
  allEntries,
  onBack,
  onSelect,
  onUpdated,
}: {
  entry: CatalogEntryView;
  allEntries: CatalogEntryView[];
  onBack: () => void;
  onSelect: (e: CatalogEntryView) => void;
  onUpdated: (e: CatalogEntryView) => void;
}) {
  const navigate = useNavigate();
  const [appearsIn, setAppearsIn] = useState<{ id: string; title: string }[]>(
    [],
  );
  const [fetching, setFetching] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setAppearsIn([]);
    void (async () => {
      const cards = await Promise.all(
        entry.source_card_ids.slice(0, 12).map((id) =>
          api
            .getCard(id)
            .then((c: any) => ({
              id,
              title: String(c?.base?.one_liner || 'Untitled card'),
            }))
            .catch(() => null),
        ),
      );
      if (!cancelled)
        setAppearsIn(cards.filter((c) => c !== null) as { id: string; title: string }[]);
    })();
    return () => {
      cancelled = true;
    };
  }, [entry.id, entry.source_card_ids]);

  const mine = new Set(entry.source_card_ids);
  const related = allEntries
    .filter(
      (e) => e.id !== entry.id && e.source_card_ids.some((id) => mine.has(id)),
    )
    .slice(0, 12);

  const hasDescription = Boolean(entry.description?.trim());
  const sources = entry.source_card_ids.length;
  const sub = subtitleOf(entry);

  const fetchInfo = async () => {
    setFetching(true);
    setFetchError(null);
    try {
      const res: any = await api.fetchCatalogInfo(entry.id);
      const updated = normalize(res.entry ?? res);
      onUpdated(updated);
    } catch {
      setFetchError("Couldn't generate details right now");
    } finally {
      setFetching(false);
    }
  };

  return (
    <div className="ct-detail">
      <div className="ct-detail-topbar">
        <button className="back-btn" onClick={onBack}>
          <CaretLeft size={16} />
          Catalog
        </button>
        <span className="ct-detail-title">{typeLabel(entry.type)}</span>
        <span style={{ width: 40 }} />
      </div>

      <div className="ct-hero">
        <span className="ct-hero-cover">
          <Cover entry={entry} iconSize={30} />
        </span>
        <div className="ct-hero-info">
          <h1 className="ct-hero-title">{entry.title}</h1>
          {sub ? <p className="ct-hero-subtitle">{sub}</p> : null}
          <span className="ct-type-pill">{typeLabel(entry.type)}</span>
          {sources > 0 ? (
            <p className="ct-refcount">
              Referenced in {sources} card{sources === 1 ? '' : 's'}
            </p>
          ) : null}
        </div>
      </div>

      <h2 className="ct-about">About</h2>
      {hasDescription ? (
        <p className="ct-desc">{entry.description!.trim()}</p>
      ) : (
        <p className="ct-nodesc">
          No detailed write-up yet. Tap “Fetch info” to have the AI generate
          an overview of what this is and what it’s about.
        </p>
      )}

      <div className="ct-actions">
        <button
          className="btn"
          onClick={() => void fetchInfo()}
          disabled={fetching}
        >
          {fetching ? (
            <span
              className="spinner"
              style={{ width: 18, height: 18 }}
              aria-hidden
            />
          ) : (
            <Sparkle size={18} />
          )}
          {fetching
            ? 'Generating…'
            : hasDescription
              ? 'Regenerate info'
              : 'Fetch info'}
        </button>
        <button
          className="ct-web-btn"
          onClick={() => window.open(lookupUrl(entry), '_blank', 'noopener')}
        >
          <ArrowUpRight size={18} />
          Search the web
        </button>
        {fetchError ? <p className="ct-err-inline">{fetchError}</p> : null}
      </div>

      {appearsIn.length > 0 ? (
        <>
          <h3 className="ct-label">Appears in</h3>
          <div>
            {appearsIn.map((c) => (
              <button
                key={c.id}
                className="ct-appears-row"
                onClick={() => navigate(`/reader/${c.id}`)}
              >
                <Article size={18} color="var(--accent)" />
                <span className="ct-appears-title">{c.title}</span>
                <CaretRight size={18} color="var(--muted)" />
              </button>
            ))}
          </div>
        </>
      ) : null}

      {related.length > 0 ? (
        <>
          <h3 className="ct-label rel">Related</h3>
          <div className="ct-related-wrap">
            {related.map((e) => (
              <button
                key={e.id}
                className="ct-related-chip"
                onClick={() => onSelect(e)}
              >
                <span className="ct-related-type">
                  {typeLabel(e.type).toUpperCase()}
                </span>
                <span className="ct-related-title">{e.title}</span>
              </button>
            ))}
          </div>
        </>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

export default function CatalogScreen() {
  const [entries, setEntries] = useState<CatalogEntryView[]>([]);
  const [selected, setSelected] = useState<CatalogEntryView | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [typeFilter, setTypeFilter] = useState<string | null>(null);

  const load = useCallback(async (withSpinner = true) => {
    if (withSpinner) setLoading(true);
    setError(null);
    try {
      const res: any = await api.listCatalog();
      const list = Array.isArray(res) ? res : [];
      setEntries(list.map(normalize).filter((e) => e.id));
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const remove = useCallback(
    async (id: string) => {
      const before = entries;
      setEntries((prev) => prev.filter((e) => e.id !== id));
      setSelected((s) => (s?.id === id ? null : s));
      try {
        await api.deleteCatalogEntry(id);
      } catch {
        setEntries(before); // resync on failure
        void load(false);
      }
    },
    [entries, load],
  );

  const onUpdated = useCallback((updated: CatalogEntryView) => {
    setEntries((prev) =>
      prev.map((e) => (e.id === updated.id ? updated : e)),
    );
    setSelected((s) => (s?.id === updated.id ? updated : s));
  }, []);

  if (selected) {
    return (
      <div className="page">
        <CatalogDetail
          entry={selected}
          allEntries={entries}
          onBack={() => setSelected(null)}
          onSelect={setSelected}
          onUpdated={onUpdated}
        />
      </div>
    );
  }

  const availableTypes = TYPE_ORDER.filter((t) =>
    entries.some((e) => e.type === t),
  );
  const entryCount = entries.length;
  const typeCount = new Set(entries.map((e) => e.type)).size;
  const referencedCardCount = new Set(
    entries.flatMap((e) => e.source_card_ids),
  ).size;

  const sections = TYPE_ORDER.filter(
    (t) => !typeFilter || t === typeFilter,
  )
    .map((t) => ({
      type: t,
      entries: entries.filter((e) => e.type === t),
    }))
    .filter((s) => s.entries.length > 0);

  return (
    <div className="page">
      {loading ? (
        <div className="ct-loading">
          <div className="spinner" aria-hidden />
        </div>
      ) : null}

      {error && !loading && entries.length === 0 ? (
        <div className="ct-msg">
          <WifiX size={52} color="var(--muted)" />
          <h2>Can&apos;t reach the backend</h2>
          <p>{error}</p>
          <button className="btn" onClick={() => void load()}>
            Retry
          </button>
        </div>
      ) : null}

      {!loading && entries.length === 0 && !error ? (
        <div className="ct-msg">
          <CatalogSpotArt />
          <h2>Nothing saved yet</h2>
          <p>
            Long-press any reference on a card to save it here — books,
            movies, apps, products, places and more.
          </p>
        </div>
      ) : null}

      {!loading && entries.length > 0 ? (
        <>
          <div className="ct-stats">
            <span className="ct-stat">
              <b>{entryCount}</b> <span>entries</span>
            </span>
            <span className="ct-stat">
              <b>{typeCount}</b> <span>types</span>
            </span>
            <span className="ct-stat">
              <b>{referencedCardCount}</b> <span>from cards</span>
            </span>
            <button
              className="ct-refresh"
              onClick={() => void load(false)}
              disabled={loading}
              aria-label="Refresh"
              title="Refresh"
            >
              <ArrowClockwise size={18} />
            </button>
          </div>

          {availableTypes.length > 0 ? (
            <div className="ct-chips">
              <button
                className={'ct-chip' + (typeFilter === null ? ' active' : '')}
                onClick={() => setTypeFilter(null)}
              >
                All
              </button>
              {availableTypes.map((t) => (
                <button
                  key={t}
                  className={'ct-chip' + (typeFilter === t ? ' active' : '')}
                  onClick={() => setTypeFilter(t)}
                >
                  {typeLabel(t)}
                </button>
              ))}
            </div>
          ) : null}

          {sections.map((s) => (
            <section key={s.type}>
              <h2 className="ct-section-label">{typeLabel(s.type)}</h2>
              <div className="ct-grid">
                {s.entries.map((e) => (
                  <ArtifactTile
                    key={e.id}
                    entry={e}
                    onOpen={() => setSelected(e)}
                    onDelete={() => void remove(e.id)}
                  />
                ))}
              </div>
            </section>
          ))}

          <div className="ct-tail">
            <CatalogSpotArt />
          </div>
        </>
      ) : null}
    </div>
  );
}
