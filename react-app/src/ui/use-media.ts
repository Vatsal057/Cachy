/**
 * useMedia — match a CSS media query reactively (the web equivalent of
 * Flutter's MediaQuery-driven layout switches). Returns whether the query
 * matches right now and re-renders when it changes.
 */
import { useEffect, useState } from 'react';

export function useMedia(query: string): boolean {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches);

  useEffect(() => {
    const mql = window.matchMedia(query);
    setMatches(mql.matches);
    const onChange = (e: MediaQueryListEvent) => setMatches(e.matches);
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, [query]);

  return matches;
}
