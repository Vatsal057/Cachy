/**
 * PrimaryActionBar — port of Flutter's primary_action_bar.dart
 * (app/lib/ui/features/reader/views/primary_action_bar.dart, docs/13).
 *
 * Floating glass bar fixed above the bottom edge: **Ask** (grounded chat),
 * the server-derived primary action when the card has one, and a "More"
 * button opening an adaptive action sheet. Handlers run client-side against
 * the card's own blocks (port of card_actions.dart) — copy / share /
 * Maps / calendar, all free.
 *
 * Note: `primaryAction` isn't declared in src/api/types.ts, so it's read
 * defensively from the card JSON — the same pattern ReaderScreen uses for
 * `insight`. When the backend doesn't serve it, the bar shows the
 * full-width "Ask this card" button, exactly like Flutter when
 * `primaryAction.isPresent` is false.
 */
import { useCallback, useMemo, useState } from 'react';
import {
  CalendarCheck,
  ChatCircle,
  Copy,
  DotsThree,
  Export,
  Link as LinkIcon,
  MapPin,
  PlayCircle,
  ShoppingCart,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import type { Block, Card } from '../../api/types';
import './reader.css';

/* ------------------------------------------------------------------ */
/* Action model — port of CardActionType / CardActionSpec / ActionResult */
/* ------------------------------------------------------------------ */

type CardActionType =
  | 'copy'
  | 'share'
  | 'openOriginal'
  | 'addToCalendar'
  | 'shoppingList'
  | 'openMaps'
  | 'openLinks';

type ActionResult = 'done' | 'copied' | 'empty' | 'failed';

interface ActionSpec {
  label: string;
  Icon: Icon;
}

const SPECS: Record<CardActionType, ActionSpec> = {
  copy: { label: 'Copy', Icon: Copy },
  share: { label: 'Share', Icon: Export },
  addToCalendar: { label: 'Add to calendar', Icon: CalendarCheck },
  openMaps: { label: 'Open in Maps', Icon: MapPin },
  shoppingList: { label: 'Shopping list', Icon: ShoppingCart },
  openLinks: { label: 'Open links', Icon: LinkIcon },
  openOriginal: { label: 'Open original', Icon: PlayCircle },
};

/* ------------------------------------------------------------------ */
/* Block helpers                                                       */
/* ------------------------------------------------------------------ */

type JsonRecord = Record<string, unknown>;

const asRecord = (b: Block): JsonRecord => b as unknown as JsonRecord;
const str = (v: unknown): string => (typeof v === 'string' ? v : '');
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const nonEmpty = (v: unknown): boolean => str(v).trim().length > 0;

/* ------------------------------------------------------------------ */
/* Primary action — server-derived dominant action (PrimaryAction in     */
/* Flutter's card.dart; wire kinds from PrimaryActionKind in enums.dart) */
/* ------------------------------------------------------------------ */

interface PrimaryAction {
  type: CardActionType;
  label: string;
}

function parsePrimaryAction(card: Card): PrimaryAction | null {
  const raw = (card as unknown as { primaryAction?: unknown }).primaryAction;
  if (!raw || typeof raw !== 'object') return null;
  const { kind, label } = raw as { kind?: unknown; label?: unknown };
  const type =
    kind === 'export'
      ? 'share'
      : kind === 'shopping_list'
        ? 'shoppingList'
        : kind === 'save_place'
          ? 'openMaps'
          : kind === 'reminder' || kind === 'schedule'
            ? 'addToCalendar'
            : null;
  const text = str(label).trim();
  // Mirrors PrimaryAction.isPresent: kind != none && label not empty.
  if (type === null || text.length === 0) return null;
  return { type, label: text };
}

/* ------------------------------------------------------------------ */
/* Available actions — content-aware, same order as Flutter's           */
/* CardActions.available: common set first, then block-unlocked ones.   */
/* ------------------------------------------------------------------ */

function availableActions(card: Card): CardActionType[] {
  const blocks = card.blocks ?? [];
  const out: CardActionType[] = ['copy', 'share', 'addToCalendar'];
  if (
    blocks.some(
      (b) => b.type === 'map' && arr(asRecord(b).places).length > 0,
    )
  ) {
    out.push('openMaps');
  }
  if (blocks.some((b) => b.type === 'checklist' || b.type === 'bullet_list')) {
    out.push('shoppingList');
  }
  if (blocks.some((b) => b.type === 'link' && nonEmpty(asRecord(b).url))) {
    out.push('openLinks');
  }
  if (nonEmpty(card.source.url)) out.push('openOriginal');
  return out;
}

/* ------------------------------------------------------------------ */
/* Markdown serialization — port of CardActions._cardToMarkdown /       */
/* _blockToMarkdown (feeds copy + share).                              */
/* ------------------------------------------------------------------ */

function blockToMarkdown(b: Block): string {
  const r = asRecord(b);
  switch (b.type) {
    case 'heading': {
      const lv = typeof r.level === 'number' ? r.level : 2;
      const level = Math.min(6, Math.max(1, Math.round(lv)));
      return `${'#'.repeat(level)} ${str(r.text)}`;
    }
    case 'paragraph':
      return str(r.text);
    case 'bullet_list':
      return arr(r.items)
        .map((i) => `- ${str(i)}`)
        .join('\n');
    case 'step_list':
      return arr(r.steps)
        .map((s, i) => `${i + 1}. ${str((s as JsonRecord).text)}`)
        .join('\n');
    case 'key_value':
      return arr(r.pairs)
        .map((p) => {
          const q = p as JsonRecord;
          return `**${str(q.key)}:** ${str(q.value)}`;
        })
        .join('\n');
    case 'checklist':
      return arr(r.items)
        .map((i) => {
          const it = i as JsonRecord;
          return `- [${it.checked === true ? 'x' : ' '}] ${str(it.text)}`;
        })
        .join('\n');
    case 'callout':
      return `> ${str(r.text)}`;
    case 'link': {
      const url = str(r.url);
      const label = str(r.label);
      return `[${label || url}](${url})`;
    }
    case 'map':
      return arr(r.places)
        .map((p) => {
          const pl = p as JsonRecord;
          const note = str(pl.note);
          return `- ${str(pl.name)}${note ? ` — ${note}` : ''}`;
        })
        .join('\n');
    case 'table': {
      const headers = arr(r.headers).map(str);
      const head = `| ${headers.join(' | ')} |`;
      const sep = `| ${headers.map(() => '---').join(' | ')} |`;
      const body = arr(r.rows)
        .map((row) => `| ${arr(row).map(str).join(' | ')} |`)
        .join('\n');
      return `${head}\n${sep}\n${body}`;
    }
    default:
      return str(r.text);
  }
}

function cardToMarkdown(card: Card): string {
  const parts: string[] = [];
  if (nonEmpty(card.base.one_liner)) parts.push(`# ${card.base.one_liner}`);
  if (nonEmpty(card.base.tldr)) parts.push(`> ${card.base.tldr}`);
  for (const b of card.blocks ?? []) {
    const md = blockToMarkdown(b);
    if (md.trim().length > 0) parts.push(md);
  }
  if (nonEmpty(card.source.url)) parts.push(`---\nSource: ${card.source.url}`);
  return parts.join('\n\n');
}

/* ------------------------------------------------------------------ */
/* Handlers — port of CardActions.perform. All best-effort: the caller  */
/* maps failures to ActionResult.failed for toast feedback.             */
/* ------------------------------------------------------------------ */

async function writeClipboard(text: string): Promise<void> {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return;
  }
  // Fallback for webviews without the async clipboard API.
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  const ok = document.execCommand('copy');
  ta.remove();
  if (!ok) throw new Error('clipboard unavailable');
}

async function shareText(text: string, title: string): Promise<ActionResult> {
  if (text.trim().length === 0) return 'empty';
  const nav = navigator as Navigator & {
    share?: (data: { title?: string; text?: string }) => Promise<void>;
  };
  if (typeof nav.share === 'function') {
    try {
      await nav.share({ title, text });
    } catch (e) {
      // Dismissing the sheet resolves like Flutter's Share.share — not a failure.
      if ((e as Error)?.name !== 'AbortError') throw e;
    }
    return 'done';
  }
  // No Web Share API (desktop browsers): degrade to clipboard.
  await writeClipboard(text);
  return 'copied';
}

function openExternal(url: string): ActionResult {
  if (url.trim().length === 0) return 'empty';
  window.open(url, '_blank', 'noopener,noreferrer');
  return 'done';
}

async function copyCard(card: Card): Promise<ActionResult> {
  const text = cardToMarkdown(card);
  if (text.trim().length === 0) return 'empty';
  await writeClipboard(text);
  return 'copied';
}

async function shareShoppingList(card: Card): Promise<ActionResult> {
  const items: string[] = [];
  for (const b of card.blocks ?? []) {
    if (b.type === 'checklist') {
      for (const it of arr(asRecord(b).items)) {
        items.push(str((it as JsonRecord).text));
      }
    } else if (b.type === 'bullet_list') {
      for (const it of arr(asRecord(b).items)) items.push(str(it));
    }
  }
  const clean = items.filter((i) => i.trim().length > 0);
  if (clean.length === 0) return 'empty';
  const title = card.base.one_liner || 'Shopping list';
  const body = `${title}\n\n${clean.map((i) => `- [ ] ${i}`).join('\n')}`;
  return shareText(body, title);
}

function firstPlace(card: Card): { name: string; lat?: number; lng?: number } | null {
  for (const b of card.blocks ?? []) {
    if (b.type !== 'map') continue;
    const raw = arr(asRecord(b).places)[0] as JsonRecord | undefined;
    if (raw && nonEmpty(raw.name)) {
      return {
        name: str(raw.name),
        lat: typeof raw.lat === 'number' ? raw.lat : undefined,
        lng: typeof raw.lng === 'number' ? raw.lng : undefined,
      };
    }
  }
  return null;
}

function openInMaps(card: Card): ActionResult {
  const place = firstPlace(card);
  const query =
    place && place.lat != null && place.lng != null
      ? `${place.lat},${place.lng}`
      : (place?.name ?? card.base.one_liner);
  if (query.trim().length === 0) return 'empty';
  return openExternal(
    `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`,
  );
}

function openFirstLink(card: Card): ActionResult {
  for (const b of card.blocks ?? []) {
    if (b.type === 'link' && nonEmpty(asRecord(b).url)) {
      return openExternal(str(asRecord(b).url));
    }
  }
  return 'empty';
}

function addToCalendar(card: Card): ActionResult {
  // Web port of add_2_calendar: download an .ics the device calendar can
  // import. Same event shape as Flutter — title, tomorrow, one hour.
  const title = card.base.one_liner || 'Cachy reminder';
  const start = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  const desc = [card.base.tldr, card.source.url]
    .filter((s) => nonEmpty(s))
    .join('\n\n');
  const stamp = (d: Date) =>
    d.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
  const esc = (s: string) =>
    s
      .replace(/\\/g, '\\\\')
      .replace(/\n/g, '\\n')
      .replace(/;/g, '\\;')
      .replace(/,/g, '\\,');
  const ics = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Cachy//Card//EN',
    'BEGIN:VEVENT',
    `UID:${Date.now()}-${Math.floor(Math.random() * 1e6)}@cachy`,
    `DTSTAMP:${stamp(new Date())}`,
    `DTSTART:${stamp(start)}`,
    `DTEND:${stamp(end)}`,
    `SUMMARY:${esc(title)}`,
    `DESCRIPTION:${esc(desc)}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
  const url = URL.createObjectURL(
    new Blob([ics], { type: 'text/calendar;charset=utf-8' }),
  );
  const a = document.createElement('a');
  a.href = url;
  a.download = `${title.replace(/[^\w\- ]+/g, '').trim() || 'Cachy reminder'}.ics`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 5000);
  return 'done';
}

async function performAction(
  card: Card,
  type: CardActionType,
): Promise<ActionResult> {
  try {
    switch (type) {
      case 'copy':
        return await copyCard(card);
      case 'share':
        return await shareText(
          cardToMarkdown(card),
          card.base.one_liner || 'Cachy card',
        );
      case 'openOriginal':
        return openExternal(card.source.url);
      case 'addToCalendar':
        return addToCalendar(card);
      case 'shoppingList':
        return await shareShoppingList(card);
      case 'openMaps':
        return openInMaps(card);
      case 'openLinks':
        return openFirstLink(card);
    }
  } catch {
    return 'failed';
  }
}

/* ------------------------------------------------------------------ */
/* PrimaryActionBar                                                    */
/* ------------------------------------------------------------------ */

export default function PrimaryActionBar({
  card,
  notify,
}: {
  card: Card;
  notify: (message: string) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);

  const primary = useMemo(() => parsePrimaryAction(card), [card]);

  const run = useCallback(
    async (type: CardActionType) => {
      // Port of HapticFeedback.lightImpact().
      try {
        navigator.vibrate(10);
      } catch {
        /* unsupported — skip */
      }
      setBusy(true);
      let result: ActionResult;
      try {
        result = await performAction(card, type);
      } catch {
        result = 'failed';
      }
      setBusy(false);
      // Port of the ActionResult → snackbar mapping in _run.
      if (result === 'copied') notify('Copied to clipboard');
      else if (result === 'empty') notify('Nothing in this card for that');
      else if (result === 'failed') notify("Couldn't complete that action");
    },
    [card, notify],
  );

  const openAsk = useCallback(() => {
    // Flutter navigates to ChatScreen here; the web app has no chat screen
    // yet, so the Ask affordance stays visible but says so plainly.
    notify('Ask chat isn\u2019t on the web app yet');
  }, [notify]);

  const chooseMore = useCallback(
    (type: CardActionType) => {
      setMoreOpen(false);
      void run(type);
    },
    [run],
  );

  // The big primary button already performs the primary type — the sheet
  // lists the rest, like Flutter's _openMore filtering out primaryType.
  const moreTypes = useMemo(
    () => availableActions(card).filter((t) => t !== primary?.type),
    [card, primary],
  );

  const PrimaryIcon: Icon | null = primary ? SPECS[primary.type].Icon : null;

  return (
    <>
      <div className="primary-action-bar" role="toolbar" aria-label="Card actions">
        <div className="pab-row">
          {primary && PrimaryIcon ? (
            <>
              <button
                type="button"
                className="pab-ask-outline"
                onClick={openAsk}
                disabled={busy}
              >
                <ChatCircle size={20} weight="regular" aria-hidden />
                Ask
              </button>
              <button
                type="button"
                className="pab-primary"
                onClick={() => void run(primary.type)}
                disabled={busy}
                aria-label={primary.label}
              >
                {busy ? (
                  <span className="pab-busy" aria-hidden />
                ) : (
                  <PrimaryIcon size={20} weight="regular" aria-hidden />
                )}
                <span className="pab-primary-label">{primary.label}</span>
              </button>
            </>
          ) : (
            <button
              type="button"
              className="pab-ask-filled"
              onClick={openAsk}
              disabled={busy}
            >
              <ChatCircle size={20} weight="regular" aria-hidden />
              Ask this card
            </button>
          )}
          <button
            type="button"
            className="icon-btn-tonal pab-more"
            onClick={() => setMoreOpen(true)}
            disabled={busy}
            aria-label="More actions"
            title="More actions"
          >
            <DotsThree size={26} weight="bold" aria-hidden />
          </button>
        </div>
      </div>

      {moreOpen && (
        <div className="sheet-backdrop" onClick={() => setMoreOpen(false)}>
          <div
            className="sheet pab-sheet"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
            aria-label="More actions"
          >
            <div className="sheet-handle" aria-hidden />
            {moreTypes.map((t) => {
              const { label, Icon: RowIcon } = SPECS[t];
              return (
                <button
                  key={t}
                  type="button"
                  className="pab-action-row"
                  onClick={() => chooseMore(t)}
                >
                  <RowIcon size={22} weight="regular" aria-hidden />
                  {label}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </>
  );
}
