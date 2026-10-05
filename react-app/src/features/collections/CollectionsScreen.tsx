/**
 * Collections — port of collections_screen.dart + folder_tile.dart.
 * Folder grid with preview faces, accent badges and count pills; rename on
 * long-press / right-click; create via the header action. The bulk
 * "Move to folder" sheet lives in FolderPicker.tsx for the library's
 * selection flow to present.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import type { CSSProperties, KeyboardEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { Folder, FolderPlus } from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import type { Card, Collection } from '../../api/types';
import { ContentType } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import { EmptyState, ErrorState, Modal } from '../../ui/feedback';
import './collections.css';

interface CollectionItem {
  collection: Collection;
  preview: Card | null;
}

type Status = 'loading' | 'ready' | 'empty' | 'error';

/* ------------------------------------------------------------------ */
/* Accent — system collections take their content-type accent; custom  */
/* folders use the clay default with a filled folder mark.             */
/* ------------------------------------------------------------------ */

function accentFor(c: Collection): { color: string; Icon: Icon; filled: boolean } {
  const st = c.system_type;
  if (!c.is_custom && st && (Object.values(ContentType) as string[]).includes(st)) {
    const a = contentAccent(st as ContentType);
    return { color: a.color, Icon: a.Icon, filled: false };
  }
  return { color: '#8A5A3C', Icon: Folder, filled: true };
}

/* FolderThumb — the preview card's face at 55% opacity (mirrors CardFace). */

function FolderThumb({ card }: { card: Card }) {
  const ref = card.media?.thumbnail ?? card.media?.keyframes?.[0] ?? null;
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    setFailed(false);
  }, [card.card_id, ref]);
  const resolveMediaFn = api.resolveMedia.bind(api);
  const src = ref && !failed ? resolveMediaFn(ref) : null;
  if (!src) return <div className="folder-accent-fallback" />;
  return <img src={src} alt="" loading="lazy" onError={() => setFailed(true)} />;
}

/* ------------------------------------------------------------------ */
/* FolderTile — port of folder_tile.dart                               */
/* ------------------------------------------------------------------ */

function FolderTile({
  item,
  onOpen,
  onRename,
}: {
  item: CollectionItem;
  onOpen: () => void;
  onRename: () => void;
}) {
  const { collection, preview } = item;
  const accent = accentFor(collection);
  const [hovered, setHovered] = useState(false);
  const pressTimer = useRef<number | null>(null);
  const suppressClick = useRef(false);

  const clearPress = () => {
    if (pressTimer.current !== null) {
      window.clearTimeout(pressTimer.current);
      pressTimer.current = null;
    }
  };

  const startPress = () => {
    suppressClick.current = false;
    clearPress();
    pressTimer.current = window.setTimeout(() => {
      suppressClick.current = true;
      onRename();
    }, 600);
  };

  const handleClick = () => {
    if (suppressClick.current) {
      suppressClick.current = false;
      return;
    }
    onOpen();
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onOpen();
    }
  };

  const BadgeIcon = accent.Icon;

  return (
    <div
      className={`folder-tile${hovered ? ' hover' : ''}`}
      role="button"
      tabIndex={0}
      aria-label={`${collection.name}, ${collection.card_count} cards`}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onContextMenu={(e) => {
        e.preventDefault();
        onRename();
      }}
      onPointerDown={startPress}
      onPointerUp={clearPress}
      onPointerLeave={clearPress}
      onPointerMove={clearPress}
      style={{ '--folder-accent': accent.color } as CSSProperties}
    >
      <div className="folder-face" aria-hidden>
        {preview?.media?.thumbnail ? (
          <FolderThumb card={preview} />
        ) : (
          <div className="folder-accent-fallback" />
        )}
      </div>
      <div className="folder-scrim" aria-hidden />
      <div className="folder-badge" aria-hidden>
        <BadgeIcon size={16} color="#fff" weight={accent.filled ? 'fill' : 'regular'} />
      </div>
      <div className="folder-count" aria-hidden>
        {collection.card_count}
      </div>
      <div className="folder-name">{collection.name.toUpperCase()}</div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* CollectionsSpot — SVG port of spot_art.dart CollectionsSpot         */
/* ------------------------------------------------------------------ */

function CollectionsSpot() {
  return (
    <svg
      width="108"
      height="76"
      viewBox="0 0 108 76"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      opacity="0.55"
      aria-hidden
    >
      <g transform="translate(56 28) rotate(2.3)">
        <path d="M-30 -14 L-10 -14 L-4 -22 L26 -22 L30 20 L-30 20 Z" />
      </g>
      <g transform="translate(52 46) rotate(-2.9)">
        <path d="M-30 -14 L-10 -14 L-4 -22 L26 -22 L30 20 L-30 20 Z" />
      </g>
    </svg>
  );
}

/* ------------------------------------------------------------------ */
/* CollectionsScreen                                                   */
/* ------------------------------------------------------------------ */

export default function CollectionsScreen() {
  const navigate = useNavigate();
  const [status, setStatus] = useState<Status>('loading');
  const [items, setItems] = useState<CollectionItem[]>([]);
  const [error, setError] = useState('');
  const [cols, setCols] = useState(2);
  const [dialog, setDialog] = useState<
    | { kind: 'create' }
    | { kind: 'rename'; collection: Collection }
    | null
  >(null);
  const [name, setName] = useState('');
  const [dialogError, setDialogError] = useState('');
  const gridRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    setStatus('loading');
    setError('');
    try {
      const entries = await api.listCollections();
      // One page of cards to pick preview thumbnails (first card with a
      // thumbnail per collection, like the Flutter view-model).
      const cards = await api.listCards({ limit: 100 }).catch(() => [] as Card[]);
      const previews = new Map<string, Card>();
      for (const c of cards) {
        const cid = c.collection_id;
        if (!cid) continue;
        const prev = previews.get(cid);
        if (!prev || (c.media?.thumbnail && !prev.media?.thumbnail)) {
          previews.set(cid, c);
        }
      }
      const visible = entries
        .filter((e) => e.card_count > 0 || e.is_custom)
        .map((e) => ({ collection: e, preview: previews.get(e.id) ?? null }));
      setItems(visible);
      setStatus(visible.length === 0 ? 'empty' : 'ready');
    } catch (e) {
      setError(friendlyError(e));
      setStatus('error');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // Columns from available width: floor(width / 180), clamped 2..7.
  useEffect(() => {
    const el = gridRef.current;
    if (!el) return;
    const compute = () => {
      const w = el.clientWidth;
      setCols(Math.min(7, Math.max(2, Math.floor(w / 180))));
    };
    compute();
    const ro = new ResizeObserver(compute);
    ro.observe(el);
    return () => ro.disconnect();
  }, [status]);

  function openDialog(d: NonNullable<typeof dialog>) {
    setName(d.kind === 'rename' ? d.collection.name : '');
    setDialogError('');
    setDialog(d);
  }

  async function submitDialog() {
    if (!dialog) return;
    const trimmed = name.trim();
    if (!trimmed) {
      setDialog(null);
      return;
    }
    try {
      if (dialog.kind === 'rename') {
        if (trimmed === dialog.collection.name) {
          setDialog(null);
          return;
        }
        const updated = await api.renameCollection(dialog.collection.id, trimmed);
        setItems((prev) =>
          prev.map((it) =>
            it.collection.id === updated.id
              ? { ...it, collection: { ...it.collection, name: updated.name } }
              : it,
          ),
        );
      } else {
        const created = await api.createCollection(trimmed);
        setItems((prev) => [...prev, { collection: created, preview: null }]);
        setStatus('ready');
      }
      setDialog(null);
    } catch {
      setDialogError(dialog.kind === 'rename' ? 'Could not rename folder' : 'Could not create folder');
    }
  }

  return (
    <div className="page">
      <div className="page-head">
        <h1 className="collections-title">COLLECTIONS</h1>
        <div className="page-head-side">
          <button
            type="button"
            className="icon-btn"
            title="New folder"
            aria-label="New folder"
            onClick={() => openDialog({ kind: 'create' })}
          >
            <FolderPlus size={22} />
          </button>
        </div>
      </div>

      {status === 'loading' && (
        <div className="collections-grid" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }} aria-label="Loading">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="tile-skeleton" />
          ))}
        </div>
      )}

      {status === 'error' && (
        <ErrorState
          title="Can't load collections"
          message={error || 'Check your connection and try again.'}
          onRetry={() => void load()}
        />
      )}

      {status === 'empty' && (
        <EmptyState
          title="No collections yet"
          message="Save a reel and Cachy will auto-sort it into a folder based on what it is — recipes, workouts, tips, and more."
          art={<CollectionsSpot />}
        />
      )}

      {status === 'ready' && (
        <div
          className="collections-grid"
          ref={gridRef}
          style={{ gridTemplateColumns: `repeat(${cols}, 1fr)` }}
        >
          {items.map((item) => (
            <FolderTile
              key={item.collection.id}
              item={item}
              onOpen={() => navigate(`/?collection=${encodeURIComponent(item.collection.id)}`)}
              onRename={() => openDialog({ kind: 'rename', collection: item.collection })}
            />
          ))}
        </div>
      )}

      {dialog && (
        <Modal
          title={dialog.kind === 'rename' ? 'Rename folder' : 'New folder'}
          onClose={() => setDialog(null)}
          actions={
            <>
              <button type="button" className="fb-text-btn" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button type="button" className="fb-filled-btn" onClick={() => void submitDialog()}>
                {dialog.kind === 'rename' ? 'Save' : 'Create'}
              </button>
            </>
          }
        >
          <input
            className="input"
            autoFocus
            placeholder="Folder name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void submitDialog();
            }}
            aria-label="Folder name"
          />
          {dialogError && <p className="fb-dialog-error">{dialogError}</p>}
        </Modal>
      )}
    </div>
  );
}
