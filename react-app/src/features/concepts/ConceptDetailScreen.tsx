import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Article, CaretLeft, CaretRight, Sparkle } from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import './concepts.css';

// Concept detail — mirrors Flutter's concept_detail_screen.dart.
// NOTE: the "Explore in chat" CTA is omitted — the React app has no chat
// surface. Re-add when a chat route exists.

interface ConceptEntryView {
  id: string;
  name: string;
  definition?: string | null;
  source_card_ids: string[];
}

interface AppearsIn {
  id: string;
  title: string;
  date: Date | null;
}

function normalize(raw: any): ConceptEntryView {
  return {
    id: String(raw.id ?? raw.concept_id ?? ''),
    name: String(raw.name ?? 'Untitled concept'),
    definition: (raw.definition as string | null | undefined) ?? null,
    source_card_ids: Array.isArray(raw.source_card_ids)
      ? raw.source_card_ids.map(String)
      : [],
  };
}

const MONTHS = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

function fmtDate(d: Date): string {
  return `${MONTHS[d.getMonth()]} ${d.getDate()}`;
}

function AppearsRow({
  entry,
  onOpen,
}: {
  entry: AppearsIn;
  onOpen: () => void;
}) {
  return (
    <button className="cn-appears-row" onClick={onOpen}>
      <span className="cn-appears-ibox">
        <Article size={17} />
      </span>
      <span className="cn-appears-title">{entry.title}</span>
      {entry.date ? (
        <span className="cn-appears-date">{fmtDate(entry.date)}</span>
      ) : null}
      <CaretRight size={16} className="cn-appears-go" />
    </button>
  );
}

// Route screen for /concepts/:id — the :id param is the source of truth.
export default function ConceptDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const conceptId = id ?? '';
  const navigate = useNavigate();
  const [entry, setEntry] = useState<ConceptEntryView | null>(null);
  const [appearsIn, setAppearsIn] = useState<AppearsIn[]>([]);
  const [related, setRelated] = useState<ConceptEntryView[]>([]);
  const [showAllAppears, setShowAllAppears] = useState(false);
  const [loading, setLoading] = useState(true);
  const [defining, setDefining] = useState(false);
  const [defineError, setDefineError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    setShowAllAppears(false);
    if (!conceptId) {
      setError('Concept not found');
      setLoading(false);
      return;
    }
    try {
      const res: any = await api.getConcept(conceptId);
      const e = normalize(res.entry ?? res);
      setEntry(e);
      const rel = Array.isArray(res.related) ? res.related : [];
      setRelated(rel.map(normalize).filter((c: ConceptEntryView) => c.id));
      // "Appears in": resolve source cards to titles (cap 12, best-effort).
      const cards = await Promise.all(
        e.source_card_ids.slice(0, 12).map((id) =>
          api
            .getCard(id)
            .then((c: any) => ({
              id,
              title: String(c?.base?.one_liner || 'Untitled card'),
              date: c?.meta?.created_at
                ? new Date(c.meta.created_at)
                : null,
            }))
            .catch(() => null),
        ),
      );
      setAppearsIn(cards.filter((c): c is AppearsIn => c !== null));
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setLoading(false);
    }
  }, [conceptId]);

  useEffect(() => {
    window.scrollTo(0, 0);
    void load();
  }, [load]);

  const define = useCallback(async () => {
    if (!conceptId) return;
    setDefining(true);
    setDefineError(null);
    try {
      const res: any = await api.defineConcept(conceptId);
      setEntry(normalize(res.entry ?? res));
    } catch {
      setDefineError("Couldn't generate definition right now");
    } finally {
      setDefining(false);
    }
  }, [conceptId]);

  const hasDefinition = Boolean(entry?.definition?.trim());
  const count = entry?.source_card_ids.length ?? 0;
  const visibleAppears = showAllAppears ? appearsIn : appearsIn.slice(0, 4);

  return (
    <div className="page" style={{ maxWidth: 728 }}>
      <div className="cn-detail-topbar">
        <button className="back-btn" onClick={() => navigate('/concepts')}>
          <CaretLeft size={16} />
          Concepts
        </button>
      </div>

      {loading ? (
        <div className="cn-loading" style={{ paddingTop: '10vh' }}>
          <div className="spinner" aria-hidden />
        </div>
      ) : null}

      {error && !loading ? (
        <div className="cn-msg" style={{ paddingTop: '10vh' }}>
          <h2>Can&apos;t load concept</h2>
          <p>{error}</p>
          <button className="btn" onClick={() => void load()}>
            Retry
          </button>
        </div>
      ) : null}

      {entry && !loading ? (
        <div className="cn-detail" style={{ paddingLeft: 0, paddingRight: 0 }}>
          <span className="cn-pill">CONCEPT</span>
          <h1 className="cn-name">{entry.name}</h1>

          {count > 0 ? (
            <div className="cn-meta">
              <span className="cn-meta-label">Last updated</span>
              <span className="cn-count-pill">
                {count} {count === 1 ? 'entry' : 'entries'}
              </span>
            </div>
          ) : null}

          <div className="cn-summary">
            <div className="cn-summary-kicker">SUMMARY</div>
            {hasDefinition ? (
              <p className="cn-summary-text">{entry.definition!.trim()}</p>
            ) : (
              <>
                <p className="cn-nosummary">
                  No summary yet — tap Define to generate one.
                </p>
                <button
                  className="cn-define-btn"
                  onClick={() => void define()}
                  disabled={defining}
                >
                  {defining ? (
                    <span
                      className="spinner"
                      style={{ width: 16, height: 16 }}
                      aria-hidden
                    />
                  ) : (
                    <Sparkle size={16} />
                  )}
                  {defining ? 'Generating…' : 'Define'}
                </button>
              </>
            )}
            {hasDefinition ? (
              <div className="cn-regen-row">
                <button
                  className="cn-regen-btn"
                  onClick={() => void define()}
                  disabled={defining}
                >
                  {defining ? (
                    <span
                      className="spinner"
                      style={{ width: 14, height: 14 }}
                      aria-hidden
                    />
                  ) : (
                    <Sparkle size={14} />
                  )}
                  {defining ? 'Regenerating…' : 'Regenerate'}
                </button>
              </div>
            ) : null}
            {defineError ? (
              <p className="cn-define-err">{defineError}</p>
            ) : null}
          </div>

          {appearsIn.length > 0 ? (
            <>
              <div className="cn-section-head">
                <h2>Appears in</h2>
                {!showAllAppears && appearsIn.length > 4 ? (
                  <button
                    className="cn-seeall"
                    onClick={() => setShowAllAppears(true)}
                  >
                    See all
                  </button>
                ) : null}
              </div>
              <div>
                {visibleAppears.map((c) => (
                  <AppearsRow
                    key={c.id}
                    entry={c}
                    onOpen={() => navigate(`/reader/${c.id}`)}
                  />
                ))}
              </div>
            </>
          ) : null}

          {related.length > 0 ? (
            <>
              <div className="cn-section-head">
                <h2>Related Concepts</h2>
              </div>
              <div className="cn-related-grid">
                {related.map((r) => (
                  <button
                    key={r.id}
                    className="cn-related-card"
                    onClick={() => navigate(`/concepts/${r.id}`)}
                  >
                    <span className="cn-related-tag">Concept</span>
                    <span className="cn-related-name">{r.name}</span>
                    {r.source_card_ids.length > 0 ? (
                      <span className="cn-related-count">
                        {r.source_card_ids.length} card
                        {r.source_card_ids.length === 1 ? '' : 's'}
                      </span>
                    ) : null}
                  </button>
                ))}
              </div>
            </>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
