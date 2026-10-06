/**
 * Rabbit-hole explorer (docs/14) — port of Flutter's
 * reader/views/rabbit_hole_screen.dart + rabbit_hole_view_model.dart.
 * Route /reader/:id/rabbithole?topic=<seed>. A generative, branching journey:
 * each step explains the tapped thread from general knowledge (not confined to
 * the card) and offers fresh threads to go one level deeper. A breadcrumb
 * trail tracks the path and lets the reader jump back to branch differently.
 */
import { useEffect, useRef, useState } from 'react';
import type { CSSProperties, ReactNode } from 'react';
import { useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { ArrowClockwise, ArrowDown, CaretRight, Cards, Compass } from 'phosphor-react';
import { api } from '../../api/client';
import type { RabbitHoleStep } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import { AlertStrip, EmptyState } from '../../ui/feedback';
import { RichInlineText } from '../../ui/rich-text';
import { ChatAppBar, goBack } from '../chat/ChatAppBar';
import { useRabbitHole } from './useRabbitHole';
import type { RabbitHole } from './useRabbitHole';
import '../chat/chat.css';
import './rabbithole.css';

export default function RabbitHoleScreen() {
  const { id = '' } = useParams<{ id: string }>();
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const location = useLocation();
  const seed = (params.get('topic') ?? '').trim();

  const back = () => goBack(navigate, location, `/reader/${encodeURIComponent(id)}`);

  // The card's content-type accent tints the whole journey (Flutter receives
  // it from the reader). Falls back to the brand accent until/unless loaded.
  const [accent, setAccent] = useState<{ id: string; color: string } | null>(null);
  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    api
      .getCard(id)
      .then((card) => {
        if (!cancelled) {
          setAccent({ id, color: contentAccent(card.base?.content_type).color });
        }
      })
      .catch(() => {
        /* keep brand accent */
      });
    return () => {
      cancelled = true;
    };
  }, [id]);

  const style = {
    '--rh-accent': accent?.id === id ? accent.color : 'var(--accent)',
  } as CSSProperties;

  if (!seed) {
    return (
      <div className="chat-screen" style={style}>
        <ChatAppBar title="Rabbit hole" onBack={back} />
        <div className="chat-center">
          <EmptyState
            icon={Compass}
            title="Nothing to explore yet"
            hint="Pick a thread from a card to start digging."
            actionLabel="Back to card"
            onAction={back}
          />
        </div>
      </div>
    );
  }

  return <Explorer cardId={id} seed={seed} onBack={back} style={style} />;
}

function Explorer({
  cardId,
  seed,
  onBack,
  style,
}: {
  cardId: string;
  seed: string;
  onBack: () => void;
  style: CSSProperties;
}) {
  const vm = useRabbitHole(cardId, seed);
  const scrollRef = useRef<HTMLDivElement>(null);

  // A new step replaces the old one — start reading it from the top.
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0 });
  }, [vm.steps.length]);

  return (
    <div className="chat-screen rh-screen" style={style}>
      <ChatAppBar title="Rabbit hole" onBack={onBack} />

      <div className="chat-scroll" ref={scrollRef}>
        <div className="chat-column rh-page">
          <Breadcrumbs vm={vm} onCard={onBack} />
          <div className="rh-gap-16" />

          {vm.loading && vm.steps.length === 0 ? (
            <div className="rh-loading-initial" role="status" aria-label="Loading">
              <span className="spinner chat-spinner-lg rh-spinner" />
            </div>
          ) : null}

          {vm.current ? (
            <StepView key={vm.steps.length} step={vm.current} vm={vm} />
          ) : null}

          {vm.busy ? <LoadingStep topic={vm.pendingTopic} /> : null}
          {vm.failure ? <ErrorStep vm={vm} /> : null}
        </div>
      </div>
    </div>
  );
}

/**
 * The path taken so far, tappable to backtrack. The first crumb is the card
 * itself (the anchor the journey started from).
 */
function Breadcrumbs({ vm, onCard }: { vm: RabbitHole; onCard: () => void }) {
  const { steps, busy, pendingTopic } = vm;
  const ref = useRef<HTMLDivElement>(null);

  // Keep the deepest crumb visible when the trail outgrows the row.
  useEffect(() => {
    const el = ref.current;
    if (el) el.scrollLeft = el.scrollWidth;
  }, [steps.length, pendingTopic]);

  if (steps.length === 0 && pendingTopic === null) return null;

  return (
    <nav className="rh-crumbs" ref={ref} aria-label="Trail">
      <Crumb label="Card" icon={<Cards size={13} weight="regular" aria-hidden />} onTap={onCard} />
      {steps.map((s, i) => {
        const isLast = i === steps.length - 1;
        return (
          <span className="rh-crumb-item" key={`${i}-${s.topic}`}>
            <Chevron />
            <Crumb
              label={s.topic}
              active={isLast}
              onTap={isLast ? undefined : () => vm.jumpTo(i)}
            />
          </span>
        );
      })}
      {busy && pendingTopic !== null && steps.length > 0 ? (
        <span className="rh-crumb-item">
          <Chevron />
          <Crumb label={pendingTopic} active dim />
        </span>
      ) : null}
    </nav>
  );
}

function Chevron() {
  return (
    <span className="rh-chevron" aria-hidden>
      <CaretRight size={12} weight="regular" />
    </span>
  );
}

function Crumb({
  label,
  icon,
  active = false,
  dim = false,
  onTap,
}: {
  label: string;
  icon?: ReactNode;
  active?: boolean;
  dim?: boolean;
  onTap?: () => void;
}) {
  return (
    <button
      type="button"
      className={`rh-crumb${active ? ' active' : ''}${dim ? ' dim' : ''}`}
      onClick={onTap}
      disabled={!onTap}
      aria-current={active && !dim ? 'step' : undefined}
      title={label}
    >
      {icon}
      <span className="rh-crumb-label">{label}</span>
    </button>
  );
}

/** One explored step: heading, explanation and the threads that branch on. */
function StepView({ step, vm }: { step: RabbitHoleStep; vm: RabbitHole }) {
  return (
    <section className="rh-step">
      <h2 className="rh-topic">{step.topic}</h2>
      <p className="rh-explanation">
        <RichInlineText text={step.explanation} />
      </p>

      {step.threads.length > 0 ? (
        <>
          <div className="rh-keep-going">
            <Compass size={15} weight="regular" aria-hidden />
            <span>KEEP GOING</span>
          </div>
          <ul className="rh-threads">
            {step.threads.map((thread, i) => (
              <li key={`${i}-${thread}`}>
                <button
                  type="button"
                  className="rh-thread"
                  disabled={vm.busy}
                  onClick={() => vm.dive(thread)}
                >
                  <span className="rh-thread-label">{thread}</span>
                  <ArrowDown size={15} weight="regular" aria-hidden />
                </button>
              </li>
            ))}
          </ul>
        </>
      ) : !vm.busy ? (
        <p className="rh-bottoms-out">
          This thread bottoms out here. Hop back to a crumb above to branch another way.
        </p>
      ) : null}
    </section>
  );
}

function LoadingStep({ topic }: { topic: string | null }) {
  return (
    <div className="rh-loading" role="status" aria-live="polite">
      <span className="spinner chat-spinner-sm rh-spinner" />
      <span className="rh-loading-text">
        {topic === null ? 'Digging…' : `Digging into "${topic}"…`}
      </span>
    </div>
  );
}

function ErrorStep({ vm }: { vm: RabbitHole }) {
  const failure = vm.failure;
  if (!failure) return null;
  return (
    <div className="rh-error">
      {failure.quota ? (
        <AlertStrip kind="warning" message={failure.message} />
      ) : (
        <>
          <p className="rh-error-text" role="alert">
            {failure.message}
          </p>
          {vm.canRetry ? (
            <button type="button" className="rh-retry" onClick={vm.retry}>
              <ArrowClockwise size={16} weight="regular" aria-hidden />
              Try again
            </button>
          ) : null}
        </>
      )}
    </div>
  );
}
