import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowClockwise,
  ArrowUpRight,
  CaretDown,
  CaretRight,
  CaretUp,
  CheckCircle,
  CloudSlash,
  Compass,
  Info,
  Lightbulb,
  Link as LinkIcon,
  Quotes,
  Shuffle,
  Sparkle,
  Target,
  X,
  XCircle,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import type { FeedCardRef, FeedItem } from '../../api/types';
import { ContentType } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import './feed.css';

// ---------------------------------------------------------------------------
// Kind metadata — mirrors Flutter's _kindMeta.
// ---------------------------------------------------------------------------

const KIND_META: Record<string, { label: string; Icon: Icon }> = {
  insight: { label: 'INSIGHT', Icon: Lightbulb },
  highlight: { label: 'HIGHLIGHT', Icon: Quotes },
  quiz: { label: 'QUICK QUIZ', Icon: Target },
  thread: { label: 'RABBIT HOLE', Icon: Compass },
  connection: { label: 'CONNECTION', Icon: LinkIcon },
};

function kindMeta(kind: string): { label: string; Icon: Icon } {
  return KIND_META[kind] ?? { label: 'MOMENT', Icon: Sparkle };
}

function accentFor(card: FeedCardRef): { color: string; Icon: Icon } {
  const a = contentAccent(card.content_type as ContentType);
  return { color: a.color, Icon: a.Icon };
}

function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(alpha * 255)
    .toString(16)
    .padStart(2, '0');
  return `${hex}${a}`;
}

// ---------------------------------------------------------------------------
// Inline rich text — mirrors Flutter's RichInlineText (**bold**, *italic*,
// `code`, [[Reference]]; refs render accent + semibold with no scope here).
// ---------------------------------------------------------------------------

let richKey = 0;

function parseRich(text: string): React.ReactNode[] {
  // Fresh regex per call: parseRich recurses for nested bold/italic, and a
  // shared /g regex would have its lastIndex clobbered by the inner call,
  // restarting the outer scan forever.
  const re =
    /\[\[(.+?)\]\]|\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`/gs;
  const parts: React.ReactNode[] = [];
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) parts.push(text.slice(last, m.index));
    const ref = m[1];
    const bold = m[2] ?? m[3];
    const italic = m[4] ?? m[5];
    const code = m[6];
    if (ref != null) {
      // Strip stray markdown chars from the label, like Flutter's
      // RichInlineText._referenceSpan does.
      const clean = ref.replace(/\*\*|__|`|\*|_/g, '').trim();
      parts.push(
        <span key={richKey++} className="fd-ref">
          {clean}
        </span>,
      );
    } else if (bold != null) {
      parts.push(
        <span key={richKey++} className="fd-b">
          {parseRich(bold)}
        </span>,
      );
    } else if (italic != null) {
      parts.push(
        <span key={richKey++} className="fd-i">
          {parseRich(italic)}
        </span>,
      );
    } else if (code != null) {
      parts.push(
        <span key={richKey++} className="fd-code">
          {code}
        </span>,
      );
    }
    last = m.index + m[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

export function RichInline({
  text,
  className,
}: {
  text: string;
  className?: string;
}) {
  return <span className={className}>{parseRich(text)}</span>;
}

// ---------------------------------------------------------------------------
// Cachy glyph + halo — mirrors Brand.CachyGlyph and EmptyState(halo: true).
// ---------------------------------------------------------------------------

function HaloGlyph() {
  return (
    <svg width={176} height={176} viewBox="0 0 176 176" aria-hidden>
      <circle
        cx={88}
        cy={88}
        r={87}
        stroke="var(--accent)"
        strokeOpacity={0.1}
        strokeWidth={1.4}
        fill="none"
      />
      <circle
        cx={88}
        cy={88}
        r={63.5}
        stroke="var(--accent)"
        strokeOpacity={0.18}
        strokeWidth={1.4}
        fill="none"
      />
      <g transform="translate(56, 56)">
        <path
          d="M 11.52 19.2 L 11.52 42.24 Q 11.52 52.48 21.76 52.48 L 42.24 52.48 Q 52.48 52.48 52.48 42.24 L 52.48 19.2"
          stroke="var(--accent)"
          strokeWidth={64 * 0.13}
          strokeLinecap="round"
          strokeLinejoin="round"
          fill="none"
        />
        <rect
          x={32 - 9.6}
          y={32 - 9.6}
          width={19.2}
          height={19.2}
          rx={19.2 * 0.32}
          fill="var(--accent)"
          fillOpacity={0.55}
        />
      </g>
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Moment pieces
// ---------------------------------------------------------------------------

function MiniCard({ card }: { card: FeedCardRef }) {
  const navigate = useNavigate();
  const accent = accentFor(card);
  const AccentIcon = accent.Icon;
  return (
    <button
      className="fd-mini"
      onClick={() => navigate(`/reader/${card.card_id}`)}
    >
      <AccentIcon size={18} color={accent.color} />
      <span className="fd-mini-title">{card.title}</span>
      <ArrowUpRight size={14} className="fd-mini-go" />
    </button>
  );
}

function SourceFooter({ item }: { item: FeedItem }) {
  const navigate = useNavigate();
  if (item.kind === 'connection') return null;
  const accent = accentFor(item.card);
  const AccentIcon = accent.Icon;
  return (
    <button
      className="fd-source"
      onClick={() => navigate(`/reader/${item.card.card_id}`)}
    >
      <AccentIcon size={16} color={accent.color} />
      <span className="fd-source-meta">
        <span className="fd-source-kicker">FROM YOUR LIBRARY</span>
        <span className="fd-source-title">{item.card.title}</span>
      </span>
      <span className="fd-source-read" style={{ color: accent.color }}>
        READ
      </span>
      <CaretRight size={14} color={accent.color} />
    </button>
  );
}

function TextMoment({ item }: { item: FeedItem }) {
  return (
    <div>
      {item.kind === 'highlight' ? (
        <div className="fd-quotes-mark">
          <Quotes size={30} weight="fill" />
        </div>
      ) : null}
      <p className="fd-pullquote">
        <RichInline text={item.text ?? ''} />
      </p>
    </div>
  );
}

function ThreadMoment({ item }: { item: FeedItem }) {
  const navigate = useNavigate();
  const accent = accentFor(item.card);
  return (
    <div>
      <p className="fd-thread-text">{item.text}</p>
      <button
        className="fd-thread-btn"
        style={{ background: accent.color }}
        onClick={() => navigate(`/reader/${item.card.card_id}`)}
      >
        <Compass size={18} />
        Fall down the rabbit hole
      </button>
    </div>
  );
}

function ConnectionMoment({ item }: { item: FeedItem }) {
  const accent = accentFor(item.card);
  if (!item.card_b) return <TextMoment item={item} />;
  return (
    <div>
      <MiniCard card={item.card} />
      <div className="fd-conn-linkrow">
        <LinkIcon size={16} color={accent.color} />
        <span>shares a thread with</span>
      </div>
      <MiniCard card={item.card_b} />
      <p className="fd-conn-blurb">
        <RichInline text={item.text ?? ''} />
      </p>
    </div>
  );
}

const QUIZ_OK = '#2e7d52';

function QuizMoment({ item }: { item: FeedItem }) {
  const [picked, setPicked] = useState<number | null>(null);
  const options = item.options ?? [];
  const answer = item.answer_index ?? 0;
  const revealed = picked !== null;
  const correct = picked === answer;
  return (
    <div>
      <p className="fd-quiz-q">{item.question}</p>
      <div>
        {options.map((opt, i) => {
          let cls = 'fd-opt';
          if (revealed) {
            cls += ' answered';
            if (i === answer) cls += ' correct';
            else if (i === picked) cls += ' wrong';
            else cls += ' dim';
          }
          return (
            <button
              key={i}
              className={cls}
              disabled={revealed}
              onClick={() => setPicked(i)}
            >
              <span className="fd-opt-text">{opt}</span>
              {revealed && i === answer ? (
                <CheckCircle size={20} weight="fill" color={QUIZ_OK} />
              ) : null}
              {revealed && i === picked && i !== answer ? (
                <XCircle
                  size={20}
                  weight="fill"
                  color="var(--danger)"
                />
              ) : null}
            </button>
          );
        })}
      </div>
      {revealed && item.explanation ? (
        <div className="fd-explain">
          {correct ? (
            <CheckCircle
              size={18}
              weight="fill"
              className="fd-explain-ok"
              color={QUIZ_OK}
            />
          ) : (
            <Info size={18} weight="fill" className="fd-explain-info" />
          )}
          <p>{item.explanation}</p>
        </div>
      ) : null}
    </div>
  );
}

function quizValid(item: FeedItem): boolean {
  const q = (item.question ?? '').trim();
  const opts = item.options ?? [];
  const a = item.answer_index ?? 0;
  return q.length > 0 && opts.length >= 2 && a >= 0 && a < opts.length;
}

function MomentBody({ item }: { item: FeedItem }) {
  if (item.kind === 'quiz' && quizValid(item))
    return <QuizMoment item={item} />;
  if (item.kind === 'thread') return <ThreadMoment item={item} />;
  if (item.kind === 'connection' && item.card_b)
    return <ConnectionMoment item={item} />;
  return <TextMoment item={item} />;
}

function MomentPage({
  item,
  showSwipeHint,
}: {
  item: FeedItem;
  showSwipeHint: boolean;
}) {
  const meta = kindMeta(item.kind);
  const accent = accentFor(item.card);
  const KindIcon = meta.Icon;
  return (
    <section
      className="fd-page"
      style={{
        background: `linear-gradient(to bottom, ${withAlpha(
          accent.color,
          0.16,
        )} 0%, var(--ground) 55%, var(--ground) 100%)`,
      }}
    >
      <div className="fd-page-inner">
        <div className="fd-eyebrow" key={`e-${item.id}`}>
          <KindIcon size={16} color={accent.color} />
          <span
            className="fd-eyebrow-label"
            style={{ color: accent.color }}
          >
            {meta.label}
          </span>
        </div>
        <div className="fd-body" key={`b-${item.id}`}>
          <div className="fd-body-scroll">
            <MomentBody item={item} />
          </div>
        </div>
        <SourceFooter item={item} />
        {showSwipeHint ? (
          <div className="fd-swipe">
            <CaretUp size={18} />
            <span>SWIPE UP</span>
          </div>
        ) : null}
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

export default function FeedScreen() {
  const navigate = useNavigate();
  const [items, setItems] = useState<FeedItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [wide, setWide] = useState(
    () =>
      typeof window !== 'undefined' &&
      window.matchMedia('(min-width: 600px)').matches,
  );
  const rootRef = useRef<HTMLDivElement>(null);
  const pagerRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const list = await api.feed(40);
      setItems(list);
      setPage(0);
      pagerRef.current?.scrollTo({ top: 0 });
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    rootRef.current?.focus({ preventScroll: true });
    const mq = window.matchMedia('(min-width: 600px)');
    const onChange = (e: MediaQueryListEvent) => setWide(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  const goTo = useCallback(
    (target: number) => {
      const el = pagerRef.current;
      if (!el || items.length === 0) return;
      const t = Math.max(0, Math.min(items.length - 1, target));
      el.scrollTo({ top: t * el.clientHeight, behavior: 'smooth' });
    },
    [items.length],
  );

  const onScroll = useCallback(() => {
    const el = pagerRef.current;
    if (!el || el.clientHeight === 0) return;
    setPage(Math.round(el.scrollTop / el.clientHeight));
  }, []);

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (items.length === 0) return;
      switch (e.key) {
        case 'ArrowDown':
        case 'PageDown':
        case 'ArrowRight':
          e.preventDefault();
          goTo(page + 1);
          break;
        case 'ArrowUp':
        case 'PageUp':
        case 'ArrowLeft':
          e.preventDefault();
          goTo(page - 1);
          break;
      }
    },
    [goTo, page, items.length],
  );

  const showControls = items.length > 1 && wide;

  return (
    <div
      className="fd-root"
      ref={rootRef}
      tabIndex={0}
      onKeyDown={onKeyDown}
      aria-label="Knowledge feed"
    >
      {loading && items.length === 0 ? (
        <div className="fd-center">
          <div className="spinner" aria-hidden />
        </div>
      ) : null}

      {error && items.length === 0 ? (
        <div className="fd-center">
          <div className="fd-err">
            <CloudSlash size={48} />
            <h2>Can&apos;t load your feed</h2>
            <p>{error}</p>
            <button className="fd-errbtn" onClick={() => void load()}>
              <ArrowClockwise size={18} />
              Try again
            </button>
          </div>
        </div>
      ) : null}

      {!loading && !error && items.length === 0 ? (
        <div className="fd-center">
          <div className="fd-empty">
            <HaloGlyph />
            <h2>Your feed is waiting</h2>
            <p>
              Save a few reels and Cachy turns them into a feed of your own
              knowledge — insights, quizzes, and surprising connections to
              swipe through.
            </p>
          </div>
        </div>
      ) : null}

      {items.length > 0 ? (
        <div className="fd-pager" ref={pagerRef} onScroll={onScroll}>
          {items.map((item, i) => (
            <MomentPage
              key={item.id}
              item={item}
              showSwipeHint={i === 0 && items.length > 1}
            />
          ))}
        </div>
      ) : null}

      <div className="fd-topbar">
        <button
          className="fd-topbtn"
          onClick={() => navigate(-1)}
          aria-label="Close"
          title="Close"
        >
          <X size={24} />
        </button>
        <span className="fd-spacer" />
        {items.length > 0 ? (
          <span className="fd-count">
            {page + 1} / {items.length}
          </span>
        ) : null}
        <span className="fd-spacer" />
        <button
          className="fd-topbtn"
          onClick={() => void load()}
          disabled={loading}
          aria-label="Shuffle"
          title="Shuffle"
        >
          <Shuffle size={24} />
        </button>
      </div>

      {showControls ? (
        <div className="fd-nav">
          <div className="fd-nav-col">
            <button
              className="fd-navbtn"
              disabled={page <= 0}
              onClick={() => goTo(page - 1)}
              aria-label="Previous"
              title="Previous"
            >
              <CaretUp size={20} />
            </button>
            <button
              className="fd-navbtn"
              disabled={page >= items.length - 1}
              onClick={() => goTo(page + 1)}
              aria-label="Next"
              title="Next"
            >
              <CaretDown size={20} />
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
