/**
 * InsightSection — port of Flutter's `reader/views/insight_section.dart`.
 *
 * The deep-analysis layer, rendered only when a card carries an `insight`
 * (idea-rich content); a simple reel shows none of this. Sections:
 * "Going deeper" header, stat strip (Read / Threads / Quiz), the "Dive deeper"
 * expander, rabbit-hole thread card, quiz card, and the deep-research prompt.
 *
 * NOTE: the backend serves `insight` on the card JSON (Flutter's Card.fromJson
 * parses it), but `src/api/types.ts` doesn't declare it — src/api/ is out of
 * bounds for this change, so the shape is declared locally and read via
 * `parseInsight`. Quiz questions are validated exactly like Flutter's
 * QuizQuestion.isValid (non-empty question, ≥2 options, answer_index in range).
 *
 * Navigation gaps (no endpoints in src/api/client.ts):
 * - Tapping a rabbit-hole thread opens the explorer screen in Flutter; the web
 *   client has no exploreRabbitHole endpoint, so taps show a toast for now.
 *   TODO(api): push a RabbitHole explorer route when the endpoint lands.
 */
import { useEffect, useState } from 'react';
import type { CSSProperties, ReactNode } from 'react';
import {
  ArrowClockwise,
  ArrowLeft,
  ArrowRight,
  Brain,
  CaretDown,
  CheckCircle,
  Compass,
  Copy,
  Export,
  FlagCheckered,
  Sparkle,
  Target,
  XCircle,
} from 'phosphor-react';
import { copyText } from './clipboard';

/* ------------------------------------------------------------------ */
/* Insight data (local mirror — see note above)                        */
/* ------------------------------------------------------------------ */

export interface RabbitHoleData {
  questions?: string[] | null;
  adjacent_topics?: string[] | null;
  advanced_concepts?: string[] | null;
}

export interface QuizQuestionData {
  question: string;
  options: string[];
  answer_index: number;
  explanation: string;
}

export interface InsightData {
  rabbit_hole?: RabbitHoleData | null;
  quiz?: Array<Record<string, unknown>> | null;
  deep_research_prompt?: string | null;
}

export interface ParsedInsight {
  threads: string[];
  quiz: QuizQuestionData[];
  deepResearchPrompt: string | null;
}

const MAX_THREADS = 5;
const COLLAPSED_THREADS = 3;

/** Mirror of Flutter's QuizQuestion.isValid. */
function validQuestion(q: Record<string, unknown>): boolean {
  const question = q['question'];
  const options = q['options'];
  const answerIndex = q['answer_index'];
  return (
    typeof question === 'string' &&
    question.trim().length > 0 &&
    Array.isArray(options) &&
    options.length >= 2 &&
    typeof answerIndex === 'number' &&
    Number.isInteger(answerIndex) &&
    answerIndex >= 0 &&
    answerIndex < options.length
  );
}

/**
 * The three rabbit-hole source lists flattened into one ordered set of starter
 * threads — questions first, then topics, then advanced concepts — deduped and
 * hard-capped at 5 (mirrors Flutter's _threads / _kMaxThreads).
 */
function collectThreads(rh: RabbitHoleData | null | undefined): string[] {
  if (!rh) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  const lists = [rh.questions, rh.adjacent_topics, rh.advanced_concepts];
  for (const list of lists) {
    for (const t of list ?? []) {
      const s = String(t ?? '');
      const key = s.toLowerCase().trim();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      out.push(s);
      if (out.length >= MAX_THREADS) return out;
    }
  }
  return out;
}

export function parseInsight(raw: unknown): ParsedInsight | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as InsightData;
  const quizRaw = Array.isArray(o.quiz) ? o.quiz : [];
  const quiz = quizRaw
    .filter((q): q is Record<string, unknown> => !!q && typeof q === 'object')
    .filter(validQuestion)
    .map((q) => ({
      question: String(q['question']),
      options: (q['options'] as unknown[]).map((x) => String(x ?? '')),
      answer_index: q['answer_index'] as number,
      explanation: typeof q['explanation'] === 'string' ? q['explanation'] : '',
    }));
  const prompt =
    typeof o.deep_research_prompt === 'string' && o.deep_research_prompt.trim()
      ? o.deep_research_prompt
      : null;
  return {
    threads: collectThreads(o.rabbit_hole),
    quiz,
    deepResearchPrompt: prompt,
  };
}

export function hasInsightContent(insight: ParsedInsight | null): boolean {
  return (
    insight !== null &&
    (insight.threads.length > 0 ||
      insight.quiz.length > 0 ||
      insight.deepResearchPrompt !== null)
  );
}

/* ------------------------------------------------------------------ */
/* InsightSection                                                      */
/* ------------------------------------------------------------------ */

export default function InsightSection({
  insight,
  accentColor,
  readMinutes,
  notify,
}: {
  insight: ParsedInsight;
  /** Content-type accent hex (Flutter's ContentAccent.color). */
  accentColor: string;
  /** Estimated read time of the card body, computed by the reader. */
  readMinutes: number;
  notify: (message: string) => void;
}) {
  const [researchOpen, setResearchOpen] = useState(false);

  const stats: { value: string; label: string; emphasize?: boolean }[] = [
    { value: `${readMinutes < 1 ? 1 : readMinutes}m`, label: 'Read' },
  ];
  if (insight.threads.length > 0) {
    stats.push({
      value: `${insight.threads.length}`,
      label: 'Threads',
      emphasize: true,
    });
  }
  if (insight.quiz.length > 0) {
    stats.push({ value: `${insight.quiz.length}`, label: 'Quiz' });
  }

  return (
    <section className="insight-section" aria-label="Going deeper">
      <div className="insight-head">
        <Brain size={16} color={accentColor} aria-hidden />
        <span style={{ color: accentColor }}>Going deeper</span>
      </div>

      <StatStrip stats={stats} accentColor={accentColor} />

      <DiveDeeper accentColor={accentColor}>
        {insight.threads.length > 0 && (
          <RabbitHoleCard
            threads={insight.threads}
            accentColor={accentColor}
            notify={notify}
          />
        )}
        {insight.quiz.length > 0 && (
          <QuizCard questions={insight.quiz} accentColor={accentColor} />
        )}
        {insight.deepResearchPrompt && (
          <button
            type="button"
            className="btn-primary btn-block"
            style={{ background: accentColor, borderColor: accentColor, color: '#fff' }}
            onClick={() => setResearchOpen(true)}
          >
            <Sparkle size={18} aria-hidden />
            Deep research prompt
          </button>
        )}
      </DiveDeeper>

      {researchOpen && insight.deepResearchPrompt && (
        <DeepResearchPanel
          prompt={insight.deepResearchPrompt}
          accentColor={accentColor}
          notify={notify}
          onClose={() => setResearchOpen(false)}
        />
      )}
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Stat strip — boxed value/label cells (port of stat_strip.dart)      */
/* ------------------------------------------------------------------ */

function StatStrip({
  stats,
  accentColor,
}: {
  stats: { value: string; label: string; emphasize?: boolean }[];
  accentColor: string;
}) {
  if (stats.length === 0) return null;
  return (
    <div className="stat-strip">
      {stats.map((s) => (
        <div key={s.label} className="stat-cell">
          <span
            className="stat-value"
            style={s.emphasize ? { color: accentColor } : undefined}
          >
            {s.value}
          </span>
          <span className="stat-label">{s.label}</span>
        </div>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Dive-deeper expander                                                */
/* ------------------------------------------------------------------ */

function DiveDeeper({
  accentColor,
  children,
}: {
  accentColor: string;
  children: ReactNode;
}) {
  const [expanded, setExpanded] = useState(false);
  const style: CSSProperties | undefined = expanded
    ? { borderColor: accentColor, borderWidth: 1.5, background: 'var(--surface-highest)' }
    : undefined;
  return (
    <div>
      <button
        type="button"
        className={`dive-deeper${expanded ? ' expanded' : ''}`}
        style={style}
        onClick={() => setExpanded((v) => !v)}
        aria-expanded={expanded}
      >
        <Compass size={20} color={accentColor} aria-hidden />
        <span className="dive-label">Dive deeper</span>
        <span className="dive-caret" aria-hidden>
          <CaretDown size={18} />
        </span>
      </button>
      {expanded && <div className="dive-body">{children}</div>}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Shared bordered panel (port of insight_section's _Panel)            */
/* ------------------------------------------------------------------ */

function Panel({
  title,
  icon,
  children,
}: {
  title: string;
  icon: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="insight-panel">
      <div className="insight-panel-head">
        <span className="insight-panel-icon" aria-hidden>
          {icon}
        </span>
        <span>{title}</span>
      </div>
      {children}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Rabbit hole                                                         */
/* ------------------------------------------------------------------ */

function RabbitHoleCard({
  threads,
  accentColor,
  notify,
}: {
  threads: string[];
  accentColor: string;
  notify: (message: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const visible = expanded ? threads : threads.slice(0, COLLAPSED_THREADS);
  const hidden = threads.length - visible.length;

  return (
    <Panel title="Rabbit hole" icon={<Compass size={18} />}>
      <p className="thread-hint">
        Tap a thread to fall in — each answer opens new ones.
      </p>
      <div>
        {visible.map((t) => (
          <button
            key={t}
            type="button"
            className="thread-row"
            onClick={() =>
              // TODO(api): Flutter pushes the rabbit-hole explorer screen here;
              // the web client has no exploreRabbitHole endpoint yet.
              notify("Rabbit-hole explorer isn't available in the web app yet")
            }
          >
            <span
              className="thread-dot"
              style={{ background: accentColor }}
              aria-hidden
            />
            <span className="thread-label">{t}</span>
            <span className="thread-go" aria-hidden>
              <ArrowRight size={14} />
            </span>
          </button>
        ))}
      </div>
      {threads.length > COLLAPSED_THREADS && (
        <button
          type="button"
          className="text-btn"
          style={{ color: accentColor }}
          onClick={() => setExpanded((v) => !v)}
        >
          {expanded ? 'Show less' : `Show ${hidden} more`}
        </button>
      )}
    </Panel>
  );
}

/* ------------------------------------------------------------------ */
/* Quiz                                                                */
/* ------------------------------------------------------------------ */

const QUIZ_CORRECT = '#2e7d52'; // Flutter's _kQuizCorrect — accent-independent

type OptState = 'idle' | 'correct' | 'wrong' | 'dim';

function QuizCard({
  questions,
  accentColor,
}: {
  questions: QuizQuestionData[];
  accentColor: string;
}) {
  const [index, setIndex] = useState(0);
  const [selected, setSelected] = useState<number | null>(null);
  const [score, setScore] = useState(0);
  const [finished, setFinished] = useState(false);

  const total = questions.length;
  const q = questions[index];
  const answered = selected !== null;
  const isLast = index + 1 >= total;

  const pick = (i: number) => {
    if (answered) return;
    setSelected(i);
    if (i === q.answer_index) setScore((s) => s + 1);
  };

  const next = () => {
    if (isLast) {
      setFinished(true);
    } else {
      setIndex((v) => v + 1);
      setSelected(null);
    }
  };

  const restart = () => {
    setIndex(0);
    setSelected(null);
    setScore(0);
    setFinished(false);
  };

  return (
    <Panel title="Test yourself" icon={<Target size={18} />}>
      {finished ? (
        <QuizResults score={score} total={total} accentColor={accentColor} onRestart={restart} />
      ) : (
        <div key={`q${index}`} className="quiz-question">
          <div className="quiz-progress">
            <div
              className="quiz-bar"
              role="progressbar"
              aria-valuenow={index + (answered ? 1 : 0)}
              aria-valuemax={total}
            >
              <div
                className="quiz-bar-fill"
                style={{
                  width: `${((index + (answered ? 1 : 0)) / total) * 100}%`,
                  background: accentColor,
                }}
              />
            </div>
            <span className="quiz-count">
              {index + 1}/{total}
            </span>
          </div>

          <h3 className="quiz-q">{q.question}</h3>

          <div>
            {q.options.map((opt, i) => {
              const state: OptState = !answered
                ? 'idle'
                : i === q.answer_index
                  ? 'correct'
                  : i === selected
                    ? 'wrong'
                    : 'dim';
              return (
                <button
                  key={i}
                  type="button"
                  className={`quiz-opt${answered ? ' answered' : ''} ${state}`}
                  onClick={() => pick(i)}
                  disabled={answered}
                >
                  <span className="quiz-opt-text">{opt}</span>
                  {state === 'correct' && (
                    <span className="opt-icon" style={{ color: QUIZ_CORRECT }} aria-hidden>
                      <CheckCircle size={18} weight="fill" />
                    </span>
                  )}
                  {state === 'wrong' && (
                    <span className="opt-icon quiz-wrong-icon" aria-hidden>
                      <XCircle size={18} weight="fill" />
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          {answered && (
            <div className="quiz-after">
              <QuizExplanation
                right={selected === q.answer_index}
                explanation={q.explanation}
              />
              <button
                type="button"
                className="btn-primary btn-block"
                style={{ background: accentColor, borderColor: accentColor, color: '#fff' }}
                onClick={next}
              >
                {isLast ? (
                  <FlagCheckered size={18} aria-hidden />
                ) : (
                  <ArrowRight size={18} aria-hidden />
                )}
                {isLast ? 'See results' : 'Next question'}
              </button>
            </div>
          )}
        </div>
      )}
    </Panel>
  );
}

function QuizExplanation({
  right,
  explanation,
}: {
  right: boolean;
  explanation: string;
}) {
  return (
    <div className={`quiz-explain${right ? ' ok' : ' bad'}`}>
      <span
        className="quiz-explain-icon"
        style={{ color: right ? QUIZ_CORRECT : 'var(--danger)' }}
        aria-hidden
      >
        {right ? (
          <CheckCircle size={18} weight="fill" />
        ) : (
          <XCircle size={18} weight="fill" />
        )}
      </span>
      <div>
        <div
          className="quiz-explain-title"
          style={{ color: right ? QUIZ_CORRECT : 'var(--danger)' }}
        >
          {right ? 'Correct' : 'Not quite'}
        </div>
        {explanation.trim() && (
          <div className="quiz-explain-body">{explanation}</div>
        )}
      </div>
    </div>
  );
}

function QuizResults({
  score,
  total,
  accentColor,
  onRestart,
}: {
  score: number;
  total: number;
  accentColor: string;
  onRestart: () => void;
}) {
  const pct = total > 0 ? score / total : 0;
  const [msg, emoji] =
    pct === 1
      ? ['Perfect run.', '🎯']
      : pct >= 0.6
        ? ['Solid — you got the gist.', '💪']
        : ['Worth another read.', '📖'];
  return (
    <div className="quiz-results">
      <div className="quiz-emoji" aria-hidden>
        {emoji}
      </div>
      <div className="quiz-score" style={{ color: accentColor }}>
        {score} / {total}
      </div>
      <p className="quiz-msg">{msg}</p>
      <button
        type="button"
        className="btn-ghost btn-block"
        style={{ color: accentColor }}
        onClick={onRestart}
      >
        <ArrowClockwise size={16} aria-hidden />
        Try again
      </button>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Deep research — ready-to-paste prompt panel (port of DeepResearchScreen) */
/* ------------------------------------------------------------------ */

function DeepResearchPanel({
  prompt,
  accentColor,
  notify,
  onClose,
}: {
  prompt: string;
  accentColor: string;
  notify: (message: string) => void;
  onClose: () => void;
}) {
  const tokenEstimate = Math.ceil(prompt.length / 4);

  const copy = () => {
    void copyText(prompt).then((ok) => {
      notify(ok ? 'Prompt copied' : "Couldn't copy the prompt");
    });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="research-overlay" role="dialog" aria-modal="true" aria-label="Deep research">
      <div className="research-top">
        <button
          type="button"
          className="circle-btn"
          onClick={onClose}
          aria-label="Back"
        >
          <ArrowLeft size={22} color="#fff" />
        </button>
        <span className="research-title">Deep research</span>
      </div>

      <div className="research-body">
        <div className="insight-head">
          <Sparkle size={16} color={accentColor} aria-hidden />
          <span style={{ color: accentColor }}>Deep research prompt</span>
        </div>
        <p className="research-sub">
          ~{tokenEstimate} tokens · paste into ChatGPT or Gemini
        </p>
        <div className="research-prompt">{prompt}</div>
      </div>

      <div className="research-foot">
        <button
          type="button"
          className="btn-primary btn-block"
          style={{ background: accentColor, borderColor: accentColor, color: '#fff' }}
          onClick={copy}
        >
          <Copy size={18} aria-hidden />
          Copy prompt
        </button>
        <button
          type="button"
          className="icon-btn-tonal"
          onClick={copy}
          aria-label="Copy prompt"
        >
          <Export size={20} aria-hidden />
        </button>
      </div>
    </div>
  );
}
