/**
 * BlockList — faithful port of Flutter's `features/blocks/block_renderer.dart`.
 *
 * - Groups the flat block list into segments: a `heading` opens a section and
 *   the flow blocks beneath it (paragraphs, lists, steps, checklists) join it
 *   inside one section card; self-carded blocks (callout/link/table/map/
 *   key_value) stand alone — except a self-carded block directly after a lone
 *   heading attaches to it, so a category heading sits as the title atop its
 *   table.
 * - All block text renders through RichInline (**bold**, *italic*, `code`,
 *   [[refs]]), matching Flutter's RichInlineText.
 * - Link-block taps and callout "Source" taps COPY the URL with a
 *   "Link copied" toast (Flutter's onOpenUrl → _copyUrl) — they never open tabs.
 * - Long-press on paragraphs, bullet items, and step rows saves a highlight
 *   (Flutter's GestureDetector.onLongPress → onHighlight), when `onHighlight`
 *   is provided (ready cards only).
 * - Checklist/step ticks are controlled: the reader owns the (optimistic,
 *   PATCH-persisted) block state and feeds it back in, so what's drawn is
 *   always what the card says. Without a toggle callback rows aren't tappable.
 * - `[[Name]]` markers resolve to the card's artifacts/concepts through
 *   ReferenceScope (Flutter's ReferenceScope InheritedWidget).
 * - Unknown/future block types degrade gracefully: render text/items when
 *   present, else skip — never crash.
 */
import { useMemo, useState } from 'react';
import type { CSSProperties, ReactNode } from 'react';
import {
  Check,
  Info,
  Link as LinkIcon,
  MapPin,
  Warning,
} from 'phosphor-react';
import type {
  Block,
  CatalogEntry,
  ConceptEntry,
  UnknownBlock,
} from '../../api/types';
import RichInline, { ReferenceScope } from './RichInline';
import type { ReferenceScopeValue } from './RichInline';
import { copyText } from './clipboard';
import { useLongPress } from './useLongPress';

/** Known block types — everything else falls through to renderUnknown. */
type KnownBlock = Exclude<Block, UnknownBlock>;
const KNOWN_TYPES = new Set([
  'heading',
  'paragraph',
  'bullet_list',
  'step_list',
  'checklist',
  'key_value',
  'callout',
  'table',
  'map',
  'link',
]);

/* ------------------------------------------------------------------ */
/* Props                                                               */
/* ------------------------------------------------------------------ */

export interface BlockListProps {
  blocks: Block[];
  /** Toggle callbacks (the reader applies them optimistically + PATCHes). */
  onToggleChecklist?: (blockId: string, index: number, checked: boolean) => void;
  onToggleStep?: (blockId: string, index: number, checked: boolean) => void;
  /** The card's referenced artifacts — resolve inline `[[Name]]` markers. */
  artifacts?: CatalogEntry[];
  onOpenArtifact?: (entry: CatalogEntry) => void;
  /** The card's concepts — resolve inline `[[idea]]` wiki-links. */
  concepts?: ConceptEntry[];
  onOpenConcept?: (concept: ConceptEntry) => void;
  /** Long-press → save highlight. Provided only for ready cards. */
  onHighlight?: (text: string) => void;
  /** Toast sink (ReaderScreen's useToast). */
  notify: (message: string) => void;
  animate?: boolean;
}

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

/** Never render javascript: links (mirrors the backend share renderer). */
function safeUrl(url: string): string | null {
  const trimmed = url.trim();
  if (/^\s*javascript:/i.test(trimmed)) return null;
  return trimmed;
}

/** Coerce heading level defensively — older rows can carry null/invalid levels. */
function headingLevel(level: number | null | undefined): 1 | 2 | 3 {
  const n = typeof level === 'number' && Number.isFinite(level) ? Math.round(level) : 2;
  if (n <= 1) return 1;
  if (n >= 3) return 3;
  return 2;
}

function asString(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function asStringArray(v: unknown): string[] {
  return Array.isArray(v) ? v.map((e) => (e == null ? '' : String(e))) : [];
}

/** A block that carries its own surface — renders standalone, not sectioned. */
function isSelfCarded(b: Block): boolean {
  return (
    b.type === 'callout' ||
    b.type === 'link' ||
    b.type === 'table' ||
    b.type === 'map' ||
    b.type === 'key_value'
  );
}

/** Group the flat block list into render segments (port of _segment). */
function segment(input: Block[]): Block[][] {
  const out: Block[][] = [];
  let section: Block[] | null = null;
  for (const b of input) {
    if (isSelfCarded(b)) {
      // A self-carded block right after a lone heading attaches to it.
      if (section !== null && section.length === 1 && section[0].type === 'heading') {
        section.push(b);
      } else {
        out.push([b]);
      }
      section = null;
    } else if (b.type === 'heading') {
      section = [b];
      out.push(section);
    } else if (section !== null) {
      section.push(b);
    } else {
      section = [b];
      out.push(section);
    }
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* BlockList                                                           */
/* ------------------------------------------------------------------ */

const STAGGER_MS = 45;
const MAX_STAGGER_INDEX = 12;

export default function BlockList({
  blocks,
  onToggleChecklist,
  onToggleStep,
  onHighlight,
  notify,
  animate = true,
  artifacts,
  onOpenArtifact,
  concepts,
  onOpenConcept,
}: BlockListProps) {
  const copyLink = (url: string) => {
    void copyText(url).then((ok) => {
      notify(ok ? 'Link copied' : "Couldn't copy the link");
    });
  };

  // Inline-reference resolver, only when there's something to resolve against.
  const scope = useMemo<ReferenceScopeValue | null>(() => {
    const hasArtifacts = !!artifacts?.length && !!onOpenArtifact;
    const hasConcepts = !!concepts?.length && !!onOpenConcept;
    if (!hasArtifacts && !hasConcepts) return null;
    const refs = new Map<string, CatalogEntry>();
    if (hasArtifacts) {
      for (const a of artifacts!) {
        if (a.title?.trim()) refs.set(a.title.toLowerCase().trim(), a);
      }
    }
    const conceptRefs = new Map<string, ConceptEntry>();
    if (hasConcepts) {
      for (const c of concepts!) {
        if (c.name?.trim()) conceptRefs.set(c.name.toLowerCase().trim(), c);
      }
    }
    return {
      refs,
      onTap: onOpenArtifact ?? (() => undefined),
      conceptRefs,
      onTapConcept: onOpenConcept,
    };
  }, [artifacts, onOpenArtifact, concepts, onOpenConcept]);

  const segments = segment(blocks ?? []);
  const root = (
    <div className="block-list-root">
      {segments.map((seg, i) => {
        const node = renderSegment(seg, i, {
          onToggleChecklist,
          onToggleStep,
          onHighlight,
          copyLink,
        });
        if (!node) return null;
        const style: CSSProperties | undefined = animate
          ? { animationDelay: `${Math.min(i, MAX_STAGGER_INDEX) * STAGGER_MS}ms` }
          : undefined;
        return (
          <div key={seg[0]?.id ?? i} className={animate ? 'block-anim' : undefined} style={style}>
            {node}
          </div>
        );
      })}
    </div>
  );
  return scope ? (
    <ReferenceScope.Provider value={scope}>{root}</ReferenceScope.Provider>
  ) : (
    root
  );
}

interface Ctx {
  onToggleChecklist?: (blockId: string, index: number, checked: boolean) => void;
  onToggleStep?: (blockId: string, index: number, checked: boolean) => void;
  onHighlight?: (text: string) => void;
  copyLink: (url: string) => void;
}

function renderSegment(seg: Block[], index: number, ctx: Ctx): ReactNode {
  if (seg.length === 1 && isSelfCarded(seg[0])) {
    return renderBlock(seg[0], ctx);
  }
  const children: ReactNode[] = [];
  for (const b of seg) {
    const w = renderBlock(b, ctx);
    if (w == null) continue;
    // Gaps inside a section card: 14px before a heading, 10px otherwise.
    const gapClass = children.length === 0 ? undefined : b.type === 'heading' ? 'seg-gap-lg' : 'seg-gap';
    children.push(
      <div key={b.id || `${index}-${children.length}`} className={gapClass}>
        {w}
      </div>,
    );
  }
  if (children.length === 0) return null;
  return <div className="section-card">{children}</div>;
}

function renderBlock(block: Block, ctx: Ctx): ReactNode {
  // UnknownBlock's index signature would otherwise poison narrowing below.
  if (!KNOWN_TYPES.has(block.type)) return renderUnknown(block, ctx);
  const b = block as KnownBlock;
  switch (b.type) {
    case 'heading': {
      const Tag = `h${headingLevel(b.level)}` as 'h1' | 'h2' | 'h3';
      return <Tag className="block-heading">{b.text ?? ''}</Tag>;
    }
    case 'paragraph':
      return <ParagraphBlock text={b.text ?? ''} onHighlight={ctx.onHighlight} />;
    case 'bullet_list':
      return <BulletListBlock items={asStringArray(b.items)} onHighlight={ctx.onHighlight} />;
    case 'step_list':
      return (
        <StepListBlock
          blockId={b.id}
          steps={(b.steps ?? []).map((s) => ({
            text: asString(s?.text),
            checkable: s?.checkable !== false,
            checked: s?.checked === true,
          }))}
          onToggle={ctx.onToggleStep}
          onHighlight={ctx.onHighlight}
        />
      );
    case 'checklist':
      return (
        <ChecklistBlock
          blockId={b.id}
          items={(b.items ?? []).map((it) => ({
            text: asString(it?.text),
            checked: it?.checked === true,
          }))}
          onToggle={ctx.onToggleChecklist}
        />
      );
    case 'key_value':
      return (
        <dl className="block-kv">
          {(b.pairs ?? []).map((pair, i) => (
            <div key={i} className="block-kv-row">
              <dt>
                <RichInline text={asString(pair?.key)} />
              </dt>
              <dd>
                <RichInline text={asString(pair?.value)} />
              </dd>
            </div>
          ))}
        </dl>
      );
    case 'callout':
      return (
        <CalloutBlock
          variant={b.variant ?? 'info'}
          text={b.text ?? ''}
          confidence={b.confidence ?? 'unverified'}
          sourceUrl={b.source_url ?? null}
          copyLink={ctx.copyLink}
        />
      );
    case 'table': {
      const headers = asStringArray(b.headers);
      const rows = (b.rows ?? [])
        .filter((r): r is string[] => Array.isArray(r))
        .map((r) => asStringArray(r));
      return (
        <div className="block-table-wrap">
          <table className="block-table">
            <thead>
              <tr>
                <th className="num-col" scope="col">
                  #
                </th>
                {headers.map((h, i) => (
                  <th key={i} scope="col">
                    <RichInline text={h} />
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row, i) => (
                <tr key={i}>
                  <td className="num-col">{i + 1}</td>
                  {headers.map((_, j) => (
                    <td key={j}>
                      <RichInline text={row[j] ?? ''} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }
    case 'map':
      return (
        <div className="place-list">
          {(b.places ?? []).map((p, i) => (
            <div key={i} className="place-row">
              <MapPin size={18} weight="regular" aria-hidden />
              <div className="place-body">
                <span className="place-name">
                  <RichInline text={asString(p?.name)} />
                </span>
                {asString(p?.note) ? (
                  <span className="place-note">
                    <RichInline text={asString(p?.note)} />
                  </span>
                ) : null}
              </div>
            </div>
          ))}
        </div>
      );
    case 'link': {
      const href = safeUrl(b.url ?? '');
      if (!href) return null;
      return (
        <button
          type="button"
          className="link-pill"
          onClick={() => ctx.copyLink(href)}
          title={href}
        >
          <LinkIcon size={18} aria-hidden />
          <span>{b.label || href}</span>
        </button>
      );
    }
    default:
      return renderUnknown(block, ctx);
  }
}

/** Forward-compat rule (docs/04): show text/items if present, else skip. */
function renderUnknown(block: Block, ctx: Ctx): ReactNode {
  const text = asString((block as { text?: unknown }).text);
  if (text.trim()) {
    return <ParagraphBlock text={text} onHighlight={ctx.onHighlight} />;
  }
  const items = asStringArray((block as { items?: unknown }).items);
  if (items.length > 0) {
    return <BulletListBlock items={items} onHighlight={ctx.onHighlight} />;
  }
  return null;
}

/* ------------------------------------------------------------------ */
/* Paragraph — long-press saves a highlight                            */
/* ------------------------------------------------------------------ */

function ParagraphBlock({
  text,
  onHighlight,
}: {
  text: string;
  onHighlight?: (text: string) => void;
}) {
  const lp = useLongPress(onHighlight ? () => onHighlight(text) : undefined);
  if (!onHighlight) {
    return (
      <p className="block-paragraph">
        <RichInline text={text} />
      </p>
    );
  }
  return (
    <p
      className="block-paragraph lp"
      onPointerDown={lp.onPointerDown}
      onPointerUp={lp.onPointerUp}
      onPointerLeave={lp.onPointerLeave}
      onPointerCancel={lp.onPointerCancel}
      onContextMenu={lp.onContextMenu}
    >
      <RichInline text={text} />
    </p>
  );
}

/* ------------------------------------------------------------------ */
/* Bullet list — 5px accent dot; long-press an item to save it         */
/* ------------------------------------------------------------------ */

function BulletListBlock({
  items,
  onHighlight,
}: {
  items: string[];
  onHighlight?: (text: string) => void;
}) {
  return (
    <ul className="block-list">
      {items.map((item, i) => (
        <BulletItem key={i} item={item} onHighlight={onHighlight} />
      ))}
    </ul>
  );
}

function BulletItem({
  item,
  onHighlight,
}: {
  item: string;
  onHighlight?: (text: string) => void;
}) {
  const lp = useLongPress(onHighlight ? () => onHighlight(item) : undefined);
  return (
    <li
      className={onHighlight ? 'lp' : undefined}
      onPointerDown={onHighlight ? lp.onPointerDown : undefined}
      onPointerUp={onHighlight ? lp.onPointerUp : undefined}
      onPointerLeave={onHighlight ? lp.onPointerLeave : undefined}
      onPointerCancel={onHighlight ? lp.onPointerCancel : undefined}
      onContextMenu={onHighlight ? lp.onContextMenu : undefined}
    >
      <RichInline text={item} />
    </li>
  );
}

/* ------------------------------------------------------------------ */
/* Step list — strip for 3+ steps, divided rows, checkable markers     */
/* ------------------------------------------------------------------ */

interface StepData {
  text: string;
  checkable: boolean;
  checked: boolean;
}

function StepListBlock({
  blockId,
  steps,
  onToggle,
  onHighlight,
}: {
  blockId: string;
  steps: StepData[];
  onToggle?: (blockId: string, index: number, checked: boolean) => void;
  onHighlight?: (text: string) => void;
}) {
  // Optimistic local toggle state. TODO(api): persist via PATCH when the
  // endpoint lands (Flutter: ReaderViewModel.toggleStep).
  const [checked, setChecked] = useState<boolean[]>(() => steps.map((s) => s.checked));

  const toggle = (index: number) => {
    const next = !checked[index];
    setChecked((prev) => prev.map((c, i) => (i === index ? next : c)));
    onToggle?.(blockId, index, next);
  };

  return (
    <div className="block-steps">
      {steps.length >= 3 && (
        <div className="step-strip" aria-hidden>
          {steps.map((_, i) => (
            <span key={i} style={{ display: 'inline-flex', alignItems: 'center' }}>
              <span className={`step-dot${checked[i] ? ' done' : ''}`}>
                {checked[i] ? <Check size={16} weight="bold" /> : i + 1}
              </span>
              {i < steps.length - 1 && <span className="step-connector" />}
            </span>
          ))}
        </div>
      )}
      <div>
        {steps.map((s, i) => (
          <StepRow
            key={i}
            number={i + 1}
            step={s}
            done={checked[i] ?? false}
            checkable={s.checkable}
            onToggle={() => toggle(i)}
            onHighlight={onHighlight ? () => onHighlight(s.text) : undefined}
          />
        ))}
      </div>
    </div>
  );
}

function StepRow({
  number,
  step,
  done,
  checkable,
  onToggle,
  onHighlight,
}: {
  number: number;
  step: StepData;
  done: boolean;
  checkable: boolean;
  onToggle: () => void;
  onHighlight?: () => void;
}) {
  const lp = useLongPress(onHighlight);

  const inner = (
    <>
      <span className={`step-marker${done ? ' done' : ''}`} aria-hidden>
        {done ? <Check size={18} weight="bold" /> : number}
      </span>
      <span className={`step-text${done ? ' done' : ''}`}>
        <RichInline text={step.text} />
      </span>
    </>
  );

  const pressable = checkable || onHighlight;
  if (!pressable) {
    return <div className="step-row">{inner}</div>;
  }
  return (
    <button
      type="button"
      className={`step-row${onHighlight ? ' lp' : ''}`}
      onClick={() => {
        // A long-press must not also flip the toggle (Flutter: onLongPress
        // never triggers onTap).
        if (lp.consumeTap()) return;
        if (checkable) onToggle();
      }}
      onPointerDown={lp.onPointerDown}
      onPointerUp={lp.onPointerUp}
      onPointerLeave={lp.onPointerLeave}
      onPointerCancel={lp.onPointerCancel}
      onContextMenu={lp.onContextMenu}
      aria-pressed={checkable ? done : undefined}
    >
      {inner}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* Checklist — circular checkboxes, strikethrough when done            */
/* ------------------------------------------------------------------ */

function ChecklistBlock({
  blockId,
  items,
  onToggle,
}: {
  blockId: string;
  items: { text: string; checked: boolean }[];
  onToggle?: (blockId: string, index: number, checked: boolean) => void;
}) {
  // Optimistic local toggle state. TODO(api): persist via PATCH when the
  // endpoint lands (Flutter: ReaderViewModel.toggleChecklistItem).
  const [checked, setChecked] = useState<boolean[]>(() => items.map((it) => it.checked));

  const toggle = (index: number) => {
    const next = !checked[index];
    setChecked((prev) => prev.map((c, i) => (i === index ? next : c)));
    onToggle?.(blockId, index, next);
  };

  return (
    <ul className="block-checklist">
      {items.map((item, i) => {
        const done = checked[i] ?? false;
        return (
          <li key={i}>
            <button
              type="button"
              className="checklist-toggle"
              onClick={() => toggle(i)}
              aria-pressed={done}
            >
              <span className={`checkbox${done ? ' checked' : ''}`} aria-hidden>
                {done && <Check size={17} weight="bold" />}
              </span>
              <span className={`checklist-text${done ? ' done' : ''}`}>
                <RichInline text={item.text} />
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

/* ------------------------------------------------------------------ */
/* Callout — variant surface, confidence chip, copy-able source link   */
/* ------------------------------------------------------------------ */

const CALLOUT_ICONS = {
  warning: Warning,
  caveat: Warning,
  source: LinkIcon,
  info: Info,
} as const;

function CalloutBlock({
  variant,
  text,
  confidence,
  sourceUrl,
  copyLink,
}: {
  variant: string;
  text: string;
  confidence: string;
  sourceUrl: string | null;
  copyLink: (url: string) => void;
}) {
  const key = (['warning', 'caveat', 'source'].includes(variant) ? variant : 'info') as keyof typeof CALLOUT_ICONS;
  const Icon = CALLOUT_ICONS[key];
  const showMeta = confidence !== 'unverified' || sourceUrl != null;
  return (
    <div className={`block-callout block-callout-${key}`}>
      <span className="callout-icon" aria-hidden>
        <Icon size={20} />
      </span>
      <div className="callout-body">
        <RichInline text={text} />
        {showMeta && (
          <div className="callout-meta">
            <span className={`confidence-chip confidence-${confidence}`}>{confidence}</span>
            {sourceUrl && (
              <button
                type="button"
                className="callout-source-link"
                onClick={() => copyLink(sourceUrl)}
              >
                Source
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
