/**
 * Render the card library as an Obsidian vault — port of Flutter's
 * data/services/obsidian_export.dart. One markdown note per card, zipped.
 * Blocks become standard markdown, tags become `#tags` so the vault has a
 * graph, and YAML frontmatter carries source/metadata.
 *
 * Like the Flutter exporter this is text-only: media (thumbnails, keyframes)
 * is not bundled — notes link back to the original reel instead. Block fields
 * are read defensively (Dart's `Block.fromJson` is tolerant of nulls and wrong
 * types) so a malformed block never aborts the whole export.
 *
 * One intentional carry-over: `type:` uses the Dart enum name
 * (`productList`, `newsExplainer`), not the wire value, to match what the
 * mobile app writes.
 */
import { api } from '../../api/client';
import type { Card } from '../../api/types';
import { buildZip } from './zip';

type Obj = Record<string, unknown>;

const PAGE_SIZE = 200; // backend `le=200`
const MAX_CARDS = 100_000; // runaway-pagination guard

// --- tolerant readers (mirror block.dart's _list/_asMap/_stringList) -------- //

const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v);
const asList = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const asObj = (v: unknown): Obj => (isObj(v) ? v : {});
const str = (v: unknown): string => (typeof v === 'string' ? v : '');
const strOrNull = (v: unknown): string | null => (typeof v === 'string' ? v : null);
const strList = (v: unknown): string[] =>
  Array.isArray(v) ? v.map((e) => (e == null ? '' : String(e))) : [];

/** Dart `ContentType.name` — snake_case wire value to lowerCamelCase. */
function contentTypeName(wire: string | undefined): string {
  switch (wire) {
    case 'recipe':
    case 'workout':
    case 'tutorial':
    case 'tip':
    case 'travel':
      return wire;
    case 'product_list':
      return 'productList';
    case 'news_explainer':
      return 'newsExplainer';
    default:
      return 'other';
  }
}

// --- helpers ----------------------------------------------------------------- //

function title(c: Card): string {
  const oneLiner = (c.base?.one_liner ?? '').trim();
  const caption = (c.source?.caption ?? '').trim();
  const raw = oneLiner || caption || `Card ${c.card_id}`;
  // First line only; titles spanning lines break the heading.
  return raw.split('\n')[0];
}

/** Filesystem- and Obsidian-link-safe note name, unique case-insensitively. */
function uniqueSlug(c: Card, used: Set<string>): string {
  let slug = title(c)
    .replace(/[\\/:*?"<>|[\]#^]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (slug.length > 80) slug = slug.substring(0, 80).trim();
  if (!slug) slug = `card-${c.card_id}`;
  let candidate = slug;
  let n = 2;
  while (used.has(candidate.toLowerCase())) {
    candidate = `${slug} (${n})`;
    n++;
  }
  used.add(candidate.toLowerCase());
  return candidate;
}

const tagSlug = (t: string): string => t.trim().replace(/\s+/g, '-');

const yaml = (s: string): string => `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;

/** ISO-8601 for the `created:` field; tz-less server stamps are kept as-is. */
function createdIso(raw: string | undefined): string | null {
  if (!raw) return null;
  const s = raw.trim();
  if (!s || Number.isNaN(new Date(s).getTime())) return null;
  return /(Z|[+-]\d{2}:?\d{2})$/i.test(s) ? new Date(s).toISOString() : s;
}

// --- block rendering --------------------------------------------------------- //

function renderTable(headers: string[], rows: string[][]): string {
  if (headers.length === 0) return '';
  const lines = [
    `| ${headers.join(' | ')} |`,
    `| ${headers.map(() => '---').join(' | ')} |`,
    ...rows.map((row) => `| ${row.join(' | ')} |`),
  ];
  return lines.join('\n').trimEnd();
}

function renderUnknown(b: Obj): string {
  const text = strOrNull(b.text);
  if (text != null && text.length > 0) return text;
  const items = strList(b.items);
  if (items.length > 0) return items.map((i) => `- ${i}`).join('\n');
  return '';
}

function renderBlock(block: unknown): string {
  const b = asObj(block);
  switch (b.type) {
    case 'heading': {
      const raw = typeof b.level === 'number' && Number.isFinite(b.level) ? Math.trunc(b.level) : 2;
      const level = Math.min(6, Math.max(2, raw));
      return `${'#'.repeat(level)} ${str(b.text)}`;
    }
    case 'paragraph':
      return str(b.text);
    case 'bullet_list':
      return strList(b.items)
        .map((i) => `- ${i}`)
        .join('\n');
    case 'step_list':
      return asList(b.steps)
        .map((s) => {
          const step = asObj(s);
          const checkable = typeof step.checkable === 'boolean' ? step.checkable : true;
          const checked = step.checked === true;
          return checkable
            ? `- [${checked ? 'x' : ' '}] ${str(step.text)}`
            : `1. ${str(step.text)}`;
        })
        .join('\n');
    case 'key_value':
      return asList(b.pairs)
        .map((p) => {
          const pair = asObj(p);
          return `- **${str(pair.key)}:** ${str(pair.value)}`;
        })
        .join('\n');
    case 'checklist':
      return asList(b.items)
        .map((i) => {
          const item = asObj(i);
          return `- [${item.checked === true ? 'x' : ' '}] ${str(item.text)}`;
        })
        .join('\n');
    case 'callout': {
      // Obsidian callout syntax.
      const variant = str(b.variant) || 'info';
      return `> [!${variant}]\n> ${str(b.text).replace(/\n/g, '\n> ')}`;
    }
    case 'link': {
      const url = str(b.url);
      return `[${strOrNull(b.label) ?? url}](${url})`;
    }
    case 'map':
      return asList(b.places)
        .map((p) => {
          const place = asObj(p);
          const note = str(place.note);
          return `- **${str(place.name)}**${note ? ` — ${note}` : ''}`;
        })
        .join('\n');
    case 'table':
      return renderTable(
        strList(b.headers),
        asList(b.rows).map((r) => strList(r)),
      );
    default:
      return renderUnknown(b);
  }
}

// --- note rendering ---------------------------------------------------------- //

function noteFor(c: Card): string {
  const out: string[] = [];
  const line = (s = '') => out.push(s);
  const t = title(c);
  const source = c.source ?? { url: '' };
  const base = c.base;
  const tags = base?.tags ?? [];

  // YAML frontmatter.
  line('---');
  line(`title: ${yaml(t)}`);
  if (source.url) line(`source: ${yaml(source.url)}`);
  if (source.platform != null) line(`platform: ${yaml(source.platform)}`);
  if (source.creator != null) line(`creator: ${yaml(source.creator)}`);
  line(`type: ${contentTypeName(base?.content_type)}`);
  const created = createdIso(c.meta?.created_at);
  if (created) line(`created: ${created}`);
  if (tags.length > 0) {
    line('tags:');
    for (const tag of tags) line(`  - ${yaml(tagSlug(String(tag)))}`);
  }
  line('---');
  line();

  line(`# ${t}`);
  line();
  if (base?.one_liner) {
    line(`> ${base.one_liner}`);
    line();
  }
  if (base?.tldr) {
    line(base.tldr);
    line();
  }

  for (const block of c.blocks ?? []) {
    const rendered = renderBlock(block);
    if (rendered) {
      line(rendered);
      line();
    }
  }

  const actions = c.action_items?.items ?? [];
  if (actions.length > 0) {
    line('## Actions');
    for (const item of actions) line(`- [${item.done ? 'x' : ' '}] ${item.text}`);
    line();
  }

  const rh = asObj(asObj(c.insight).rabbit_hole);
  const questions = strList(rh.questions);
  const adjacent = strList(rh.adjacent_topics);
  const advanced = strList(rh.advanced_concepts);
  if (questions.length + adjacent.length + advanced.length > 0) {
    line('## Rabbit hole');
    for (const q of questions) line(`- ${q}`);
    for (const a of adjacent) line(`- [[${tagSlug(a)}]]`);
    for (const a of advanced) line(`- [[${tagSlug(a)}]]`);
    line();
  }

  if (source.url) {
    line('---');
    line(`[Original reel](${source.url})`);
  }
  if (tags.length > 0) {
    line();
    line(tags.map((tag) => `#${tagSlug(String(tag))}`).join(' '));
  }

  // Dart's StringBuffer.writeln terminates every line with '\n'.
  return out.join('\n') + '\n';
}

const readme = (count: number): string =>
  `# Cachy export\n\n${count} card(s) exported as an Obsidian vault. ` +
  'Open the `Cachy` folder as a vault in Obsidian.\n';

// --- public API -------------------------------------------------------------- //

/** Build the vault `.zip` bytes from [cards]. */
export function buildVault(cards: Card[]): Uint8Array {
  const encoder = new TextEncoder();
  const used = new Set<string>();
  const modified = new Date();
  const entries = cards.map((card) => ({
    name: `Cachy/${uniqueSlug(card, used)}.md`,
    data: encoder.encode(noteFor(card)),
    modified,
  }));
  entries.push({
    name: 'Cachy/README.md',
    data: encoder.encode(readme(cards.length)),
    modified,
  });
  return buildZip(entries);
}

/**
 * Every card, paginated to the backend's per-request cap (Flutter's
 * `listAll`). Bypasses the GET cache so the vault reflects the server, and
 * fetches the full card when a list item arrives without its blocks.
 */
export async function fetchAllCards(): Promise<Card[]> {
  const all: Card[] = [];
  for (let offset = 0; offset < MAX_CARDS; offset += PAGE_SIZE) {
    const page = await api.listCards({ limit: PAGE_SIZE, offset }, { ttlMs: 0 });
    all.push(...page);
    if (page.length < PAGE_SIZE) break;
  }
  return Promise.all(
    all.map((c) =>
      Array.isArray(c.blocks) ? c : api.getCard(c.card_id, { ttlMs: 0 }).catch(() => c),
    ),
  );
}

/** Hand [bytes] to the browser as a file download. */
export function downloadBytes(bytes: Uint8Array, filename: string, mime: string): void {
  const blob = new Blob([bytes as BlobPart], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  // Give the browser a tick to start the download before releasing the blob.
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

export const VAULT_FILENAME = 'cachy-vault.zip';

/**
 * Fetch every card, build the vault and trigger the download.
 * Returns the number of cards exported (0 = nothing to export, no download).
 */
export async function exportVault(): Promise<number> {
  const cards = await fetchAllCards();
  if (cards.length === 0) return 0;
  downloadBytes(buildVault(cards), VAULT_FILENAME, 'application/zip');
  return cards.length;
}
