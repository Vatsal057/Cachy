/**
 * Product/artifact lookup — port of Flutter's
 * `catalog/services/artifact_lookup.dart` (docs/09). Turns a catalog entry
 * into a "go find/buy this" link: routes by artifact type to a free, keyless
 * web destination (store search, library, IMDb, Maps…) and opens it in a new
 * tab. Best-effort: failures return false, never throw.
 */
import type { CatalogEntry } from '../../api/types';

/** Build the lookup URL for an artifact (pure, so it's testable). */
export function lookupUrl(entry: CatalogEntry): string {
  const q = [entry.title, entry.creator ?? '']
    .filter((s) => s.trim().length > 0)
    .join(' ');
  // Dart's Uri.encodeQueryComponent: spaces become '+'.
  const query = new URLSearchParams({ q: q || entry.title })
    .toString()
    .slice(2);

  switch (entry.type) {
    case 'product':
      return `https://www.google.com/search?tbm=shop&q=${query}`;
    case 'book':
      return `https://www.google.com/search?tbm=bks&q=${query}`;
    case 'movie':
    case 'tv_show':
      return `https://www.imdb.com/find/?q=${query}`;
    case 'podcast':
    case 'music':
      return `https://music.apple.com/search?term=${query}`;
    case 'place':
      return `https://www.google.com/maps/search/?api=1&query=${query}`;
    case 'app':
    case 'other':
    default:
      // Plain Google search — apps aren't always on one store.
      return `https://www.google.com/search?q=${query}`;
  }
}

/** Open the lookup destination for an artifact. Returns false on failure. */
export function openLookup(entry: CatalogEntry): boolean {
  try {
    // With `noopener` browsers return null even on success, so success here
    // just means "didn't throw".
    window.open(lookupUrl(entry), '_blank', 'noopener,noreferrer');
    return true;
  } catch {
    return false;
  }
}
