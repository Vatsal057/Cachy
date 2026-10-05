/**
 * Full-text search over the library — port of search_screen.dart.
 * Debounced query (300ms) with stale-response discard, the search field living in the header like the
 * Flutter AppBar, designed empty / no-results / error states, and a result
 * wall reusing CardTile with the content-type filter bar.
 */
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { MagnifyingGlass, MagnifyingGlassMinus, X } from 'phosphor-react';
import { api } from '../../api/client';
import type { Card } from '../../api/types';
import { ContentType } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import { EmptyState, ErrorState } from '../../ui/feedback';
import CardTile from '../library/CardTile';
import './search.css';

type Status = 'idle' | 'loading' | 'results' | 'empty' | 'error';

/** Content types present in the results, in order of first appearance. */
function presentTypes(results: Card[]): ContentType[] {
  const seen: ContentType[] = [];
  for (const c of results) {
    if (!seen.includes(c.base.content_type)) seen.push(c.base.content_type);
  }
  return seen;
}

export default function SearchScreen() {
  const navigate = useNavigate();
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [results, setResults] = useState<Card[]>([]);
  const [filter, setFilter] = useState<ContentType | null>(null);
  const [attempt, setAttempt] = useState(0);
  const [cols, setCols] = useState(2);
  const gridRef = useRef<HTMLDivElement>(null);
  /** Monotonic id of the latest search request — older in-flight responses are stale. */
  const requestId = useRef(0);
  const trimmed = query.trim();

  useEffect(() => {
    if (!trimmed) {
      setStatus('idle');
      setResults([]);
      return;
    }
    setStatus('loading');
    // A newer keystroke (or retry) starts a newer request; when an older
    // in-flight response lands late it is discarded as stale.
    const id = ++requestId.current;
    const t = window.setTimeout(async () => {
      try {
        const cards = await api.search(trimmed);
        if (requestId.current !== id) return; // stale — a newer query fired
        setResults(cards);
        setFilter(null); // reset filter on a fresh query
        setStatus(cards.length === 0 ? 'empty' : 'results');
      } catch {
        if (requestId.current !== id) return; // stale — a newer query fired
        setStatus('error');
      }
    }, 300);
    return () => window.clearTimeout(t);
  }, [trimmed, attempt]);

  // Columns from available width: floor(width / 200), clamped 2..5.
  useEffect(() => {
    const el = gridRef.current;
    if (!el) return;
    const compute = () => {
      const w = el.clientWidth;
      setCols(Math.min(5, Math.max(2, Math.floor(w / 200))));
    };
    compute();
    const ro = new ResizeObserver(compute);
    ro.observe(el);
    return () => ro.disconnect();
  }, [status]);

  const types = presentTypes(results);
  const visible = filter === null ? results : results.filter((c) => c.base.content_type === filter);
  const count = filter === null ? results.length : visible.length;

  function clear() {
    setQuery('');
  }

  return (
    <div className="page">
      <header className="search-bar">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search your cards…"
          autoFocus
          autoCapitalize="off"
          autoCorrect="off"
          enterKeyHint="search"
          aria-label="Search your cards"
        />
        {trimmed && (
          <button
            type="button"
            className="search-clear"
            onClick={clear}
            aria-label="Clear search"
          >
            <X size={20} />
          </button>
        )}
      </header>

      {status === 'idle' && (
        <EmptyState
          icon={MagnifyingGlass}
          title="Search everything"
          message="Find a recipe step, a place, a product — across every card you've saved."
        />
      )}

      {status === 'loading' && (
        <div className="loading">
          <div className="spinner" aria-hidden />
        </div>
      )}

      {status === 'error' && (
        <ErrorState
          message="Couldn't reach search. Check your connection and try again."
          onRetry={() => setAttempt((a) => a + 1)}
        />
      )}

      {status === 'empty' && (
        <EmptyState
          icon={MagnifyingGlassMinus}
          title="No matches"
          message={`Nothing matched "${trimmed}". Try a different word, or capture a reel about it.`}
          actionLabel="Capture a reel"
          onAction={() => navigate('/capture')}
        />
      )}

      {status === 'results' && (
        <>
          <p className="search-count">
            {count} {count === 1 ? 'result' : 'results'}
          </p>
          <div className="search-chips" role="toolbar" aria-label="Filter by content type">
            <button
              type="button"
              className={`search-chip${filter === null ? ' active' : ''}`}
              onClick={() => setFilter(null)}
            >
              All
            </button>
            {types.map((t) => (
              <button
                key={t}
                type="button"
                className={`search-chip${filter === t ? ' active' : ''}`}
                onClick={() => setFilter(t)}
              >
                {contentAccent(t).label}
              </button>
            ))}
          </div>
          <div
            className="search-grid"
            ref={gridRef}
            style={{ gridTemplateColumns: `repeat(${cols}, 1fr)` }}
          >
            {visible.map((card) => (
              <CardTile
                key={card.card_id}
                card={card}
                onTap={() => navigate(`/reader/${encodeURIComponent(card.card_id)}`)}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
