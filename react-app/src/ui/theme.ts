/**
 * Theme mode (System / Light / Dark) — port of Flutter's AppController theme
 * state. Persisted in localStorage and applied via `data-theme` on <html>
 * (index.css honors [data-theme='light']; dark is the default).
 *
 * `initTheme()` runs once at startup (main.tsx) so a reload keeps the user's
 * choice without needing the Profile screen to mount first.
 */

export type ThemeMode = 'system' | 'light' | 'dark';

export const THEME_KEY = 'cachy_theme';

export function readTheme(): ThemeMode {
  try {
    const v = localStorage.getItem(THEME_KEY);
    return v === 'light' || v === 'dark' ? v : 'system';
  } catch {
    return 'system';
  }
}

export function applyTheme(mode: ThemeMode): void {
  const dark =
    mode === 'dark' ||
    (mode === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
}

/** Persist + apply. Storage failures (private mode) still apply for the session. */
export function setTheme(mode: ThemeMode): void {
  try {
    localStorage.setItem(THEME_KEY, mode);
  } catch {
    /* private mode — applies for this session */
  }
  applyTheme(mode);
}

let installed = false;

/** Apply the saved theme and follow OS changes while in 'system' mode. */
export function initTheme(): void {
  applyTheme(readTheme());
  if (installed) return;
  installed = true;
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  mq.addEventListener('change', () => {
    if (readTheme() === 'system') applyTheme('system');
  });
}
