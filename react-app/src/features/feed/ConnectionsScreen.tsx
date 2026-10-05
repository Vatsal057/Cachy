import { useNavigate } from 'react-router-dom';
import {
  ArrowClockwise,
  ArrowUpRight,
  CloudSlash,
  Link as LinkIcon,
  LinkSimple,
  Plus,
  Sparkle,
} from 'phosphor-react';
import type { FeedCardRef } from '../../api/types';
import { ContentType } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import { RichInline } from './FeedScreen';
import './feed.css';

// The serendipity engine's own surface — mirrors Flutter's connections_screen.
//
// Props-driven on purpose: the connections endpoint is not in src/api (off
// limits for this pass). Wire `api.connections()` + a `/connections` route in
// App.tsx, then feed this component: connections, loading, refreshing, error,
// onFindMore, onRetry.

export interface ConnectionView {
  cardA: FeedCardRef;
  cardB: FeedCardRef;
  blurb: string;
}

export interface ConnectionsScreenProps {
  connections: ConnectionView[];
  loading: boolean;
  refreshing: boolean;
  error: string | null;
  onFindMore: () => void;
  onRetry: () => void;
}

function accentColor(contentType: string): string {
  return contentAccent(contentType as ContentType).color;
}

function accentIcon(contentType: string) {
  return contentAccent(contentType as ContentType).Icon;
}

function MiniCard({ card }: { card: FeedCardRef }) {
  const navigate = useNavigate();
  const Icon = accentIcon(card.content_type);
  const color = accentColor(card.content_type);
  return (
    <button
      className="fd-cnx-mini"
      onClick={() => navigate(`/reader/${card.card_id}`)}
    >
      <span
        className="fd-cnx-ibox"
        style={{ background: `${color}1f` /* 12% */ }}
      >
        <Icon size={18} color={color} />
      </span>
      <span className="fd-cnx-mini-title">{card.title}</span>
      <ArrowUpRight size={15} className="fd-cnx-mini-go" />
    </button>
  );
}

function ConnectionCard({
  connection,
  index,
}: {
  connection: ConnectionView;
  index: number;
}) {
  return (
    <article
      className="fd-cnx-card"
      style={{ animationDelay: `${30 * (index + 1)}ms` }}
    >
      <MiniCard card={connection.cardA} />
      <div className="fd-cnx-mid">
        <LinkSimple size={15} />
      </div>
      <MiniCard card={connection.cardB} />
      <p className="fd-cnx-blurb">
        <RichInline text={connection.blurb ?? ''} />
      </p>
    </article>
  );
}

export default function ConnectionsScreen({
  connections,
  loading,
  refreshing,
  error,
  onFindMore,
  onRetry,
}: ConnectionsScreenProps) {
  const empty = !loading && !error && connections.length === 0;

  return (
    <div className="page">
      <div className="fd-cnx">
        <div className="fd-cnx-head">
          <h1 className="fd-cnx-title">Connections</h1>
          <button
            className="fd-topbtn"
            onClick={onFindMore}
            disabled={refreshing}
            aria-label="Find more"
            title="Find more"
          >
            {refreshing ? (
              <span
                className="spinner"
                style={{ width: 18, height: 18 }}
                aria-hidden
              />
            ) : (
              <Sparkle size={24} />
            )}
          </button>
        </div>

        {loading ? (
          <div className="loading">
            <div className="spinner" aria-hidden />
          </div>
        ) : null}

        {error ? (
          <div className="fd-cnx-list">
            <div className="fd-err" style={{ padding: '48px 0' }}>
              <CloudSlash size={48} />
              <h2>Can&apos;t load connections</h2>
              <p>{error}</p>
              <button className="fd-errbtn" onClick={onRetry}>
                <ArrowClockwise size={18} />
                Try again
              </button>
            </div>
          </div>
        ) : null}

        {empty ? (
          <div className="fd-cnx-list">
            <div className="fd-empty" style={{ padding: '48px 24px' }}>
              <span
                style={{
                  width: 76,
                  height: 76,
                  borderRadius: '50%',
                  background: 'var(--surface-high)',
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: 'var(--muted)',
                }}
              >
                <LinkIcon size={34} />
              </span>
              <h2>No connections yet</h2>
              <p>
                Connections surface surprising links between your cards. Save
                a few more from different topics, then tap Find more.
              </p>
              <button
                className="btn"
                style={{ marginTop: 24 }}
                onClick={onFindMore}
              >
                <Plus size={20} />
                Find connections
              </button>
            </div>
          </div>
        ) : null}

        {!loading && !error && connections.length > 0 ? (
          <>
            <p className="fd-cnx-intro">
              Surprising threads Cachy found between cards across your library.
            </p>
            <div className="fd-cnx-list">
              {connections.map((c, i) => (
                <ConnectionCard key={i} connection={c} index={i} />
              ))}
            </div>
          </>
        ) : null}
      </div>
    </div>
  );
}
