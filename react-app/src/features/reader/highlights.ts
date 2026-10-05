/**
 * Local highlight store — mirrors the Flutter highlight flow in
 * `reader_screen.dart` (`onHighlight` → `HighlightStore.add` → "Saved to
 * highlights" toast).
 *
 * Flutter's Highlight: id (timestamp), cardId, cardTitle, text,
 * colorIndex (highlights.length % 5), createdAt.
 *
 * TODO(api): src/api/client.ts exposes no highlight endpoints, so saves are
 * local-only (this browser, localStorage). When the backend adds highlight
 * persistence, replace this module with server calls — the reader already
 * funnels every save through `addHighlight`, so the swap is one file.
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
