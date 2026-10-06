/**
 * RichInline — port of Flutter's `ui/core/widgets/rich_text.dart` RichInlineText.
 *
 * Parses the same inline grammar: `[[Reference]]`, **bold** / __bold__,
 * *italic* / _italic_, and `code`. Bold/italic nest recursively, exactly like
 * the Dart `_spans` implementation.
 *
 * `[[Name]]` markers resolve through ReferenceScope (Flutter's InheritedWidget
 * of the same name): first against the card's catalog artifacts, then against
 * its concepts; a resolved marker becomes a tappable link, an unresolved one
 * (or no scope in the tree) renders as its bare styled name.
 */
import { createContext, useContext } from 'react';
import type { KeyboardEvent, ReactNode } from 'react';
import type { CatalogEntry, ConceptEntry } from '../../api/types';

/** Inline grammar: `[[Reference]]`, then **bold**, *italic* / _italic_, `code`. */
const RICH_RE =
  /\[\[(.+?)\]\]|\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`/gs;

/** Carries the card's inline-reference resolver down to RichInline. */
export interface ReferenceScopeValue {
  /** normalised title → artifact */
  refs: Map<string, CatalogEntry>;
  onTap: (entry: CatalogEntry) => void;
  /** normalised name → concept (wiki-links for the card's concepts) */
  conceptRefs: Map<string, ConceptEntry>;
  onTapConcept?: (concept: ConceptEntry) => void;
}

export const ReferenceScope = createContext<ReferenceScopeValue | null>(null);

function cleanRefLabel(label: string): string {
  return label.replace(/\*\*|__|`|\*|_/g, '').trim();
}

/** Keyboard activation for the span-as-link refs. */
function activateOnKey(e: KeyboardEvent, fn: () => void) {
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    fn();
  }
}

function renderRef(
  label: string,
  key: string,
  scope: ReferenceScopeValue | null,
): ReactNode {
  const clean = cleanRefLabel(label);
  const norm = clean.toLowerCase().trim();
  const entry = scope?.refs.get(norm);
  const concept = scope?.conceptRefs.get(norm);
  const tap = entry
    ? () => scope!.onTap(entry)
    : concept && scope?.onTapConcept
      ? () => scope.onTapConcept!(concept)
      : null;
  if (!tap) {
    return (
      <span key={key} className="rich-ref">
        {clean}
      </span>
    );
  }
  return (
    <span
      key={key}
      className="rich-ref rich-ref-link"
      role="link"
      tabIndex={0}
      onClick={tap}
      onKeyDown={(e) => activateOnKey(e, tap)}
      // A press on a link must never start the parent's long-press highlight.
      onPointerDown={(e) => e.stopPropagation()}
    >
      {clean}
    </span>
  );
}

function renderRich(
  text: string,
  keyPrefix: string,
  scope: ReferenceScopeValue | null,
): ReactNode[] {
  const nodes: ReactNode[] = [];
  let last = 0;
  let k = 0;
  for (const m of text.matchAll(RICH_RE)) {
    const start = m.index ?? 0;
    if (start > last) nodes.push(text.slice(last, start));
    const ref = m[1];
    if (ref != null) {
      nodes.push(renderRef(ref, `${keyPrefix}r${k++}`, scope));
    } else if (m[2] != null || m[3] != null) {
      nodes.push(
        <strong key={`${keyPrefix}b${k++}`}>
          {renderRich(m[2] ?? m[3] ?? '', `${keyPrefix}b${k}`, scope)}
        </strong>,
      );
    } else if (m[4] != null || m[5] != null) {
      nodes.push(
        <em key={`${keyPrefix}i${k++}`}>
          {renderRich(m[4] ?? m[5] ?? '', `${keyPrefix}i${k}`, scope)}
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
  const scope = useContext(ReferenceScope);
  return <>{renderRich(text, 'x', scope)}</>;
}
