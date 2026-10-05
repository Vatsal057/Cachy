/**
 * RichInline — port of Flutter's `ui/core/widgets/rich_text.dart` RichInlineText.
 *
 * Parses the same inline grammar: `[[Reference]]`, **bold** / __bold__,
 * *italic* / _italic_, and `code`. Bold/italic nest recursively, exactly like
 * the Dart `_spans` implementation.
 *
 * NOTE (reference scope): Flutter resolves `[[Name]]` markers against the
 * card's artifacts/concepts via ReferenceScope. The web API client
 * (src/api/client.ts) exposes no cardArtifacts/cardConcepts endpoints, so refs
 * render as their bare styled name (which is what Flutter does when no
 * ReferenceScope is in the tree). TODO(api): wire a resolver when endpoints land.
 */
import type { ReactNode } from 'react';

/** Inline grammar: `[[Reference]]`, then **bold**, *italic* / _italic_, `code`. */
const RICH_RE =
  /\[\[(.+?)\]\]|\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`/gs;

function cleanRefLabel(label: string): string {
  return label.replace(/\*\*|__|`|\*|_/g, '').trim();
}

function renderRich(text: string, keyPrefix: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  let last = 0;
  let k = 0;
  for (const m of text.matchAll(RICH_RE)) {
    const start = m.index ?? 0;
    if (start > last) nodes.push(text.slice(last, start));
    const ref = m[1];
    if (ref != null) {
      // Reference marker — bare styled name (no resolver scope on web yet).
      nodes.push(
        <span key={`${keyPrefix}r${k++}`} className="rich-ref">
          {cleanRefLabel(ref)}
        </span>,
      );
    } else if (m[2] != null || m[3] != null) {
      nodes.push(
        <strong key={`${keyPrefix}b${k++}`}>
          {renderRich(m[2] ?? m[3] ?? '', `${keyPrefix}b${k}`)}
        </strong>,
      );
    } else if (m[4] != null || m[5] != null) {
      nodes.push(
        <em key={`${keyPrefix}i${k++}`}>
          {renderRich(m[4] ?? m[5] ?? '', `${keyPrefix}i${k}`)}
        </em>,
      );
    } else if (m[6] != null) {
      nodes.push(
        <code key={`${keyPrefix}c${k++}`} className="rich-code">
          {m[6]}
        </code>,
      );
    }
    last = start + m[0].length;
  }
  if (last < text.length) nodes.push(text.slice(last));
  return nodes;
}

export default function RichInline({ text }: { text: string }) {
  return <>{renderRich(text, 'x')}</>;
}
