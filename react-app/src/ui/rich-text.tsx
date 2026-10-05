/**
 * RichInlineText — shared port of Flutter's ui/core/widgets/rich_text.dart.
 * Inline rich-text renderer for LLM-generated prose: **bold**, *italic* /
 * _italic_, `code`, plus [[Reference]] markers that resolve to tappable
 * artifacts when a ReferenceScope is in the tree. Without a scope, refs
 * render as their bare styled name.
 */
import { createContext, useContext } from 'react';
import type { ReactNode } from 'react';
import './widgets.css';

export interface ReferenceTarget {
  /** Normalised lookup key is derived from the label. */
  label: string;
}

interface ReferenceScopeValue {
  refs: Record<string, ReferenceTarget>;
  onTap: (entry: ReferenceTarget) => void;
  conceptRefs?: Record<string, ReferenceTarget>;
  onTapConcept?: (entry: ReferenceTarget) => void;
}

const ReferenceScopeContext = createContext<ReferenceScopeValue | null>(null);

/**
 * Carries the card's inline-reference resolver down to rich-text widgets, so
 * a [[Name]] marker becomes a tappable link without drilling params.
 */
export function ReferenceScope({
  refs,
  onTap,
  conceptRefs,
  onTapConcept,
  children,
}: ReferenceScopeValue & { children: ReactNode }) {
  return (
    <ReferenceScopeContext.Provider
      value={{ refs, onTap, conceptRefs, onTapConcept }}
    >
      {children}
    </ReferenceScopeContext.Provider>
  );
}

let richKey = 0;

function parseRich(
  text: string,
  scope: ReferenceScopeValue | null,
): ReactNode[] {
  // Fresh regex per call: parseRich recurses for nested bold/italic, and a
  // shared /g regex would have its lastIndex clobbered by the inner call.
  const re =
    /\[\[(.+?)\]\]|\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`/gs;
  const parts: ReactNode[] = [];
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) parts.push(text.slice(last, m.index));
    const ref = m[1];
    const bold = m[2] ?? m[3];
    const italic = m[4] ?? m[5];
    const code = m[6];
    if (ref != null) {
      const clean = ref.replace(/\*\*|__|`|\*|_/g, '').trim();
      const key = clean.toLowerCase();
      const entry = scope?.refs[key];
      const concept = !entry ? scope?.conceptRefs?.[key] : undefined;
      const tappable =
        (entry && scope) || (concept && scope?.onTapConcept);
      parts.push(
        tappable ? (
          <button
            key={richKey++}
            type="button"
            className="rt-ref"
            onClick={() =>
              entry ? scope!.onTap(entry) : scope!.onTapConcept!(concept!)
            }
          >
            {clean}
          </button>
        ) : (
          <span key={richKey++} className="rt-ref">
            {clean}
          </span>
        ),
      );
    } else if (bold != null) {
      parts.push(
        <strong key={richKey++} className="rt-b">
          {parseRich(bold, scope)}
        </strong>,
      );
    } else if (italic != null) {
      parts.push(
        <em key={richKey++} className="rt-i">
          {parseRich(italic, scope)}
        </em>,
      );
    } else if (code != null) {
      parts.push(
        <code key={richKey++} className="rt-code">
          {code}
        </code>,
      );
    }
    last = m.index + m[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

export function RichInlineText({
  text,
  className,
}: {
  text: string;
  className?: string;
}) {
  const scope = useContext(ReferenceScopeContext);
  return <span className={className}>{parseRich(text, scope)}</span>;
}
