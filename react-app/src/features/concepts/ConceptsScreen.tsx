import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowClockwise,
  Lightbulb,
  WifiX,
} from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import './concepts.css';

// The concepts browser — mirrors Flutter's concepts_screen.dart: a flat wrap of
// labeled chips (no thumbnails), stat strip on top, long-press to delete.

interface ConceptView {
  id: string;
  name: string;
  definition?: string | null;
  source_card_ids: string[];
}

function normalize(raw: any): ConceptView {
  return {
    id: String(raw.id ?? raw.concept_id ?? ''),
    name: String(raw.name ?? 'Untitled concept'),
    definition: (raw.definition as string | null | undefined) ?? null,
    source_card_ids: Array.isArray(raw.source_card_ids)
      ? raw.source_card_ids.map(String)
      : [],
  };
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
  confirmLabel,
  onCancel,
  onConfirm,
}: {
  title: string;
  message: string;
  confirmLabel: string;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="cn-dialog-backdrop" onClick={onCancel}>
      <div
        className="cn-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
      >
        <h3>{title}</h3>
        <p>{message}</p>
        <div className="cn-dialog-actions">
          <button className="cn-dialog-cancel" onClick={onCancel}>
            Cancel
          </button>
          <button className="cn-dialog-remove" onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

function ConceptChip({
  entry,
  onOpen,
  onDelete,
}: {
  entry: ConceptView;
  onOpen: () => void;
  onDelete: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const lp = useLongPress(() => setConfirming(true));
  const count = entry.source_card_ids.length;
  return (
    <>
      <button className="cn-chip" onClick={onOpen} {...lp}>
        <Lightbulb size={14} color="var(--accent)" />
        <span className="cn-chip-name">{entry.name}</span>
        {count > 1 ? <span className="cn-badge">{count}</span> : null}
      </button>
      {confirming ? (
        <ConfirmDialog
          title="Remove concept?"
          message={`"${entry.name}" will be removed from your library.`}
          confirmLabel="Remove"
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

export default function ConceptsScreen() {
  const navigate = useNavigate();
  const [concepts, setConcepts] = useState<ConceptView[]>([]);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (withSpinner = true) => {
    if (withSpinner) setLoading(true);
    setError(null);
    try {
      const res: any = await api.listConcepts({ limit: 200 });
      const list = Array.isArray(res) ? res : [];
      setConcepts(list.map(normalize).filter((c) => c.id));
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
      const before = concepts;
      setConcepts((prev) => prev.filter((c) => c.id !== id));
      try {
        await api.deleteConcept(id);
      } catch {
        setConcepts(before); // resync on failure
        void load(false);
      }
    },
    [concepts, load],
  );

  const q = query.trim().toLowerCase();
  const filtered = q
    ? concepts.filter((c) => c.name.toLowerCase().includes(q))
    : concepts;
  const referencedCardCount = new Set(
    concepts.flatMap((c) => c.source_card_ids),
  ).size;

  return (
    <div className="page">
      {loading ? (
        <div className="cn-loading">
          <div className="spinner" aria-hidden />
        </div>
      ) : null}

      {error && !loading && concepts.length === 0 ? (
        <div className="cn-msg">
          <WifiX size={52} color="var(--muted)" />
          <h2>Can&apos;t reach the backend</h2>
          <p>{error}</p>
          <button className="btn" onClick={() => void load()}>
            Retry
          </button>
        </div>
      ) : null}

      {!loading && concepts.length === 0 && !error ? (
        <div className="cn-msg">
          <Lightbulb size={52} color="var(--muted)" />
          <h2>No concepts yet</h2>
          <p>
            Concepts emerge automatically once recurring themes connect across
            multiple saved reels. Keep capturing idea-rich content!
          </p>
        </div>
      ) : null}

      {!loading && concepts.length > 0 ? (
        <>
          <div className="cn-stats">
            <div className="cn-stat emph">
              <b>{concepts.length}</b>
              <span>Concepts</span>
            </div>
            <div className="cn-stat">
              <b>{referencedCardCount}</b>
              <span>From cards</span>
            </div>
          </div>

          <div
            style={{
              display: 'flex',
              gap: 8,
              alignItems: 'center',
              margin: '20px 0 12px',
            }}
          >
            <input
              className="input search-input"
              type="search"
              placeholder="Filter concepts…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Filter concepts"
            />
            <button
              className="cn-iconbtn"
              onClick={() => void load(false)}
              aria-label="Refresh"
              title="Refresh"
            >
              <ArrowClockwise size={20} />
            </button>
          </div>

          {filtered.length === 0 ? (
            <p className="muted" style={{ fontSize: 14 }}>
              No concepts match your filter.
            </p>
          ) : (
            <div className="cn-chips">
              {filtered.map((c) => (
                <ConceptChip
                  key={c.id}
                  entry={c}
                  onOpen={() => navigate(`/concepts/${c.id}`)}
                  onDelete={() => void remove(c.id)}
                />
              ))}
            </div>
          )}
        </>
      ) : null}
    </div>
  );
}
