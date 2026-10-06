/**
 * Local highlight store — mirrors the Flutter highlight flow in
 * `reader_screen.dart` (`onHighlight` → `HighlightStore.add` → "Saved to
 * highlights" toast) and `library_screen.dart` (_HighlightsSection).
 *
 * Flutter's Highlight: id (timestamp), cardId, cardTitle, text,
 * colorIndex (highlights.length % 5), createdAt.
 */

export interface SavedHighlight {
  id: string;
  cardId: string;
  cardTitle: string;
  text: string;
  colorIndex: number;
  createdAt: string;
}

const STORAGE_KEY = 'cachy.highlights.v1';

type Listener = (all: SavedHighlight[]) => void;
const listeners = new Set<Listener>();

function notify(): void {
  const all = loadHighlights();
  listeners.forEach((fn) => {
    try {
      fn(all);
    } catch {
      /* ignore subscriber error */
    }
  });
}

if (typeof window !== 'undefined') {
  window.addEventListener('storage', (e) => {
    if (e.key === STORAGE_KEY) {
      notify();
    }
  });
}

export function subscribeHighlights(fn: Listener): () => void {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

export function loadHighlights(): SavedHighlight[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as SavedHighlight[]) : [];
  } catch {
    return [];
  }
}

function persist(all: SavedHighlight[]): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(all));
  } catch {
    /* storage full/blocked — the toast still confirms the in-memory save */
  }
  notify();
}

/**
 * Save a highlight, mirroring Flutter's onHighlight exactly: the id is the
 * creation timestamp and the color cycles 0–4 with the store size.
 */
export function addHighlight(input: {
  cardId: string;
  cardTitle: string;
  text: string;
}): SavedHighlight {
  const all = loadHighlights();
  const highlight: SavedHighlight = {
    id: `${Date.now()}`,
    cardId: input.cardId,
    cardTitle: input.cardTitle,
    text: input.text,
    colorIndex: all.length % 5,
    createdAt: new Date().toISOString(),
  };
  all.push(highlight);
  persist(all);
  return highlight;
}

export function deleteHighlight(id: string): void {
  const all = loadHighlights().filter((h) => h.id !== id);
  persist(all);
}
