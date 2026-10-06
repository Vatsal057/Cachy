/**
 * Profile ("You") — port of profile_screen.dart.
 * Shelf header + stat strip, then Appearance / Library / About / Account
 * sections with the Flutter copy, dialogs and toasts intact.
 *
 * Web notes: Google account rows, the backup banner, "Claim a Cachy ID" and
 * the Offline AI (on-device model) section are N/A — web auth is
 * Cachy-ID-only, the route requires a session, and a browser can't run the
 * local model. Export-as-vault builds a zip in the browser and downloads it
 * (Flutter hands it to the OS share sheet).
 */
import { useCallback, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  At,
  CaretRight,
  ClockCounterClockwise,
  Export,
  Gauge,
  Hash,
  Info,
  InstagramLogo,
  Monitor,
  Moon,
  SignOut,
  Sun,
  Trash,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api, ApiException } from '../../api/client';
import type { Card, QuotaStatus } from '../../api/types';
import { useAuth } from '../auth/AuthContext';
import { Modal, useToast } from '../../ui/feedback';
import { readTheme, setTheme } from '../../ui/theme';
import type { ThemeMode } from '../../ui/theme';
import { DEV_UNLOCK_KEY } from '../dev/DevScreen';
import { exportVault } from './obsidian-export';
import './profile.css';

/* ------------------------------------------------------------------ */
/* Theme — SegmentedButton parity via data-theme (index.css honors     */
/* [data-theme='light']; dark is the default).                         */
/* ------------------------------------------------------------------ */

// Theme state lives in ui/theme.ts (applied at startup in main.tsx).

/* ------------------------------------------------------------------ */
/* CachyGlyph — exact port of brand.dart _GlyphPainter (reel resting   */
/* in the bracket, reelDrop = 1).                                      */
/* ------------------------------------------------------------------ */

function CachyGlyph({ size = 44 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" fill="none" aria-hidden>
      <path
        d="M18 30 L18 66 A16 16 0 0 0 34 82 L66 82 A16 16 0 0 0 82 66 L82 30"
        stroke="var(--ink)"
        strokeWidth="13"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect x="35" y="35" width="30" height="30" rx="9.6" fill="var(--accent)" />
    </svg>
  );
}

/* ------------------------------------------------------------------ */
/* _Tile — raised row, accent leading icon, optional chevron           */
/* ------------------------------------------------------------------ */

function Tile({
  icon: Leading,
  title,
  sub,
  trailing,
  onClick,
  destructive,
  showChevron = true,
  label,
}: {
  icon: Icon;
  title: string;
  sub?: string;
  trailing?: ReactNode;
  onClick?: () => void;
  destructive?: boolean;
  showChevron?: boolean;
  label?: string;
}) {
  const content = (
    <>
      <span className={`p-tile-icon${destructive ? ' danger' : ''}`} aria-hidden>
        <Leading size={22} />
      </span>
      <span className="p-tile-body">
        <span className={`p-tile-title${destructive ? ' danger' : ''}`}>{title}</span>
        {sub && <span className="p-tile-sub">{sub}</span>}
      </span>
      {trailing ??
        (onClick && showChevron ? (
          <CaretRight size={18} className="p-tile-chevron" aria-hidden />
        ) : null)}
    </>
  );
  const cls = `p-tile${onClick ? ' tappable' : ''}`;
  return onClick ? (
    <button type="button" className={cls} onClick={onClick} aria-label={label ?? title}>
      {content}
    </button>
  ) : (
    <div className={cls}>{content}</div>
  );
}

function Section({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section className="p-section">
      <h2 className="p-section-label">{label}</h2>
      {children}
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Dialogs                                                             */
/* ------------------------------------------------------------------ */

type DialogState =
  | { kind: 'clear-cache' }
  | { kind: 'sign-out' }
  | { kind: 'dev' }
  | { kind: 'instagram' }
  | { kind: 'restore-name' }
  | { kind: 'restore-confirm'; name: string }
  | null;

/** Verified against profile_screen.dart (`_kDeveloperPassword`). */
const DEVELOPER_PASSWORD = 'vatxzz';

/** Instagram handles: letters, digits, periods, underscores; max 30. */
const IG_HANDLE_RE = /^[A-Za-z0-9._]{1,30}$/;

/**
 * localStorage keys this app owns that hold cached (re-downloadable) data.
 * Anything with "cache" in a `cachy_` / `cachy:` / `cachy.` key qualifies;
 * the auth token, username, theme, onboarding flag, API override, split-pane
 * width and saved highlights (user data) never match.
 */
const CACHE_KEY_RE = /^cachy[_:.].*cache/i;

/** Drop the in-memory API cache plus any owned localStorage caches. */
function clearOfflineCache(): void {
  api.invalidate('');
  try {
    const doomed: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k && CACHE_KEY_RE.test(k)) doomed.push(k);
    }
    doomed.forEach((k) => localStorage.removeItem(k));
  } catch {
    /* private mode — nothing persisted to clear */
  }
}

/** Raw server detail when available — mirrors Flutter's `'$e'` interpolation. */
function errText(e: unknown): string {
  if (e instanceof ApiException) return e.detail || e.message;
  return e instanceof Error ? e.message : String(e);
}

/* ------------------------------------------------------------------ */
/* ProfileScreen                                                       */
/* ------------------------------------------------------------------ */

export default function ProfileScreen() {
  const navigate = useNavigate();
  const { user, logout } = useAuth();
  const { showToast, toastNode } = useToast();

  const [themeMode, setThemeMode] = useState<ThemeMode>(readTheme);
  const [cardCount, setCardCount] = useState<number | null>(null);
  const [weekCount, setWeekCount] = useState<number | null>(null);
  const [refCount, setRefCount] = useState<number | null>(null);
  const [statsNonce, setStatsNonce] = useState(0);
  const [quota, setQuota] = useState<QuotaStatus | null>(null);
  const [quotaFailed, setQuotaFailed] = useState(false);
  const [dialog, setDialog] = useState<DialogState>(null);
  const [devPassword, setDevPassword] = useState('');
  const [versionTaps, setVersionTaps] = useState(0);
  const [exporting, setExporting] = useState(false);

  // Instagram auto-save
  const [igLinked, setIgLinked] = useState<string | null>(null);
  const [igHandle, setIgHandle] = useState('');
  const [igBusy, setIgBusy] = useState(false);
  const [igError, setIgError] = useState<string | null>(null);

  // Legacy library restore
  const [restoreName, setRestoreName] = useState('');
  const [restoreBusy, setRestoreBusy] = useState(false);

  /* Theme */
  // Persist + apply; the OS-change listener for 'system' lives in initTheme().
  useEffect(() => {
    setTheme(themeMode);
  }, [themeMode]);

  /* Stat strip — exact counts, paginating like the library does. */
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const all: Card[] = [];
        for (let offset = 0; offset < 10000; offset += 200) {
          const page = await api.listCards({ limit: 200, offset });
          all.push(...page);
          if (page.length < 200) break;
        }
        if (!alive) return;
        setCardCount(all.length);
        const weekAgo = Date.now() - 7 * 86400000;
        setWeekCount(
          all.filter((c) => {
            const t = c.meta?.created_at ? new Date(c.meta.created_at).getTime() : 0;
            return t > weekAgo;
          }).length,
        );
      } catch {
        if (alive) {
          setCardCount(0);
          setWeekCount(0);
        }
      }
    })();
    (async () => {
      let total = 0;
      try {
        for (let offset = 0; offset < 5000; offset += 200) {
          const page = await api.listCatalog({ limit: 200, offset });
          total += page.length;
          if (page.length < 200) break;
        }
      } catch {
        total = 0; // Flutter: catalog().catchError((_) => []) → shows 0
      }
      if (alive) setRefCount(total);
    })();
    return () => {
      alive = false;
    };
  }, [statsNonce]);

  /* Quota meter — hidden while loading or on any error. */
  useEffect(() => {
    let alive = true;
    api
      .quota()
      .then((q) => {
        if (alive) setQuota(q);
      })
      .catch(() => {
        if (alive) setQuotaFailed(true);
      });
    return () => {
      alive = false;
    };
  }, []);

  /* Linked Instagram handle — any error reads as "not linked". */
  useEffect(() => {
    let alive = true;
    api
      .getInstagramLink()
      .then((h) => {
        if (alive) setIgLinked(h && h.length > 0 ? h : null);
      })
      .catch(() => {
        if (alive) setIgLinked(null);
      });
    return () => {
      alive = false;
    };
  }, []);

  const showQuota = !quotaFailed && quota?.cards != null && quota?.chat != null;

  function unlockDev() {
    setDialog(null);
    if (devPassword === DEVELOPER_PASSWORD) {
      setDevPassword('');
      try {
        sessionStorage.setItem(DEV_UNLOCK_KEY, '1');
      } catch {
        /* private mode — the flag won't persist past reload */
      }
      showToast('Developer mode unlocked');
      navigate('/dev');
    } else {
      setDevPassword('');
      showToast('Incorrect password');
    }
  }

  function onVersionTap() {
    const taps = versionTaps + 1;
    setVersionTaps(taps);
    if (taps >= 7) {
      setVersionTaps(0);
      setDevPassword('');
      setDialog({ kind: 'dev' });
    }
  }

  /* ── Export as Obsidian vault ── */
  async function onExportVault() {
    setExporting(true);
    try {
      const n = await exportVault();
      showToast(
        n === 0
          ? 'No cards to export yet'
          : `Vault exported — ${n} ${n === 1 ? 'card' : 'cards'}`,
      );
    } catch {
      showToast('Export failed — try again');
    } finally {
      setExporting(false);
    }
  }

  /* ── Clear offline cache ── */
  function onClearCache() {
    setDialog(null);
    clearOfflineCache();
    showToast('Offline cache cleared');
    setStatsNonce((n) => n + 1);
  }

  /* ── Instagram auto-save ── */
  const openInstagram = useCallback(() => {
    setIgHandle(igLinked ? `@${igLinked}` : '');
    setIgError(null);
    setDialog({ kind: 'instagram' });
  }, [igLinked]);

  async function saveInstagram() {
    if (igBusy) return;
    const input = igHandle.trim();
    if (!input) {
      setIgError('Enter your Instagram username.');
      return;
    }
    if (!IG_HANDLE_RE.test(input.replace(/^@+/, ''))) {
      setIgError('Usernames use letters, numbers, periods and underscores (30 max).');
      return;
    }
    setIgBusy(true);
    setIgError(null);
    try {
      const saved = await api.linkInstagram(input);
      setIgLinked(saved);
      setDialog(null);
      showToast(`Linked @${saved}! Send reels to @cachyapp`);
    } catch (e) {
      setIgError(`Failed to link Instagram: ${errText(e)}`);
    } finally {
      setIgBusy(false);
    }
  }

  async function unlinkInstagram() {
    if (igBusy) return;
    setIgBusy(true);
    setIgError(null);
    try {
      await api.unlinkInstagram();
      setIgLinked(null);
      setDialog(null);
      showToast('Unlinked Instagram account');
    } catch (e) {
      setIgError(`Failed to unlink: ${errText(e)}`);
    } finally {
      setIgBusy(false);
    }
  }

  /* ── Restore old library ── */
  function submitRestoreName() {
    const name = restoreName.trim();
    setDialog(name ? { kind: 'restore-confirm', name } : null);
  }

  async function runClaim(name: string) {
    if (restoreBusy) return;
    setRestoreBusy(true);
    try {
      const n = await api.claimLegacyLibrary(name);
      setDialog(null);
      showToast(
        n === 0 ? 'Nothing to restore' : `Restored ${n} ${n === 1 ? 'card' : 'cards'}`,
      );
      if (n > 0) setStatsNonce((x) => x + 1);
    } catch (e) {
      setDialog(null);
      if (e instanceof ApiException && e.status === 409) {
        showToast('That name was already claimed.');
      } else if (e instanceof ApiException && e.status === 404) {
        showToast("Restoring old libraries isn't enabled on this server right now.");
      } else {
        showToast('Restore failed — try again');
      }
    } finally {
      setRestoreBusy(false);
    }
  }

  return (
    <div className="page">
      <div className="page-head">
        <h1 className="profile-title">You</h1>
      </div>

      <div className="p-shelf">
        <CachyGlyph size={44} />
        <h2 className="p-shelf-title">Your shelf</h2>
      </div>

      <div className="p-stats" role="group" aria-label="Library stats">
        <div className="p-stat">
          <span className="p-stat-value accent">{cardCount ?? '—'}</span>
          <span className="p-stat-label">Cards</span>
        </div>
        <div className="p-stat">
          <span className="p-stat-value">{weekCount ?? '—'}</span>
          <span className="p-stat-label">This week</span>
        </div>
        <div className="p-stat">
          <span className="p-stat-value">{refCount ?? '—'}</span>
          <span className="p-stat-label">References</span>
        </div>
      </div>

      <Section label="Appearance">
        <div className="seg-tabs" role="radiogroup" aria-label="Theme">
          {(
            [
              { mode: 'system', label: 'System', Icon: Monitor },
              { mode: 'light', label: 'Light', Icon: Sun },
              { mode: 'dark', label: 'Dark', Icon: Moon },
            ] as const
          ).map(({ mode, label, Icon: SegIcon }) => (
            <button
              key={mode}
              type="button"
              role="radio"
              aria-checked={themeMode === mode}
              className={`seg-tab${themeMode === mode ? ' active' : ''}`}
              onClick={() => setThemeMode(mode)}
            >
              <SegIcon size={15} aria-hidden />
              {label}
            </button>
          ))}
        </div>
      </Section>

      <Section label="Library">
        <Tile
          icon={Export}
          title={exporting ? 'Preparing vault…' : 'Export as Obsidian vault'}
          sub="Saves every card as a markdown note, zipped to open in Obsidian."
          onClick={exporting ? undefined : () => void onExportVault()}
          trailing={exporting ? <span className="p-spinner" role="status" aria-label="Preparing vault" /> : undefined}
        />
        <Tile
          icon={Trash}
          title="Clear offline cache"
          sub="Removes locally saved cards. They re-download when opened."
          onClick={() => setDialog({ kind: 'clear-cache' })}
        />
        {showQuota && (
          <Tile
            icon={Gauge}
            title="AI usage today"
            sub={`${quota!.cards!.used}/${quota!.cards!.limit} cards · ${quota!.chat!.used}/${quota!.chat!.limit} chats`}
            showChevron={false}
          />
        )}
      </Section>

      <Section label="About">
        <Tile
          icon={Info}
          title="Cachy"
          sub="Turn the reels you save into things you can actually use. Cards live on this device."
        />
        <Tile
          icon={Hash}
          title="Version"
          sub="1.0.2"
          onClick={onVersionTap}
          showChevron={false}
          label="Version 1.0.2"
        />
      </Section>

      <Section label="Account">
        {user && <Tile icon={At} title="Cachy ID" sub={`@${user}`} showChevron={false} />}
        <Tile
          icon={InstagramLogo}
          title={igLinked ? `Instagram: @${igLinked}` : 'Auto-save from Instagram'}
          sub={
            igLinked
              ? 'Send reels to @cachyapp on Instagram to auto-save them.'
              : 'Link your Instagram handle to auto-save reels sent to @cachyapp.'
          }
          onClick={openInstagram}
        />
        <Tile
          icon={ClockCounterClockwise}
          title="Restore old library"
          sub="Used Cachy before with a name? Bring those cards in."
          onClick={() => {
            setRestoreName('');
            setDialog({ kind: 'restore-name' });
          }}
        />
        <Tile
          icon={SignOut}
          title="Sign out"
          sub="Your cards stay safe in your account."
          destructive
          onClick={() => setDialog({ kind: 'sign-out' })}
        />
      </Section>

      {/* ── Clear offline cache ── */}
      {dialog?.kind === 'clear-cache' && (
        <Modal
          title="Clear offline cache?"
          onClose={() => setDialog(null)}
          actions={
            <div className="p-actions">
              <button type="button" className="p-btn p-btn-text" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button type="button" className="p-btn p-btn-filled" onClick={onClearCache}>
                Clear
              </button>
            </div>
          }
        >
          <p className="p-dialog-copy">
            Locally saved copies are removed. Cards re-download when you open them.
          </p>
        </Modal>
      )}

      {/* ── Developer gate ── */}
      {dialog?.kind === 'dev' && (
        <Modal
          title="Developer access"
          onClose={() => setDialog(null)}
          actions={
            <div className="p-actions">
              <button type="button" className="p-btn p-btn-text" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button type="button" className="p-btn p-btn-filled" onClick={unlockDev}>
                Unlock
              </button>
            </div>
          }
        >
          <label className="p-field-label" htmlFor="dev-password">
            Password
          </label>
          <input
            id="dev-password"
            className="input"
            type="password"
            autoFocus
            value={devPassword}
            onChange={(e) => setDevPassword(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') unlockDev();
            }}
          />
        </Modal>
      )}

      {/* ── Instagram auto-save ── */}
      {dialog?.kind === 'instagram' && (
        <Modal
          title="Instagram Auto-Save"
          onClose={() => setDialog(null)}
          actions={
            <div className="p-actions">
              {igLinked && (
                <button
                  type="button"
                  className="p-btn p-btn-text danger"
                  disabled={igBusy}
                  onClick={() => void unlinkInstagram()}
                >
                  Unlink
                </button>
              )}
              <span className="p-actions-spacer" />
              <button type="button" className="p-btn p-btn-text" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="p-btn p-btn-filled"
                disabled={igBusy}
                onClick={() => void saveInstagram()}
              >
                {igBusy ? 'Saving…' : 'Save'}
              </button>
            </div>
          }
        >
          <p className="p-dialog-copy">
            Link your Instagram username. Once linked, any reel you DM or share to @cachyapp
            will automatically appear on your Cachy shelf.
          </p>
          <label className="p-field-label" htmlFor="ig-handle">
            Instagram username
          </label>
          <div className="p-input-wrap">
            <At size={18} aria-hidden />
            <input
              id="ig-handle"
              className="input"
              autoFocus={!igLinked}
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              placeholder="@username"
              value={igHandle}
              aria-invalid={igError ? true : undefined}
              onChange={(e) => {
                setIgHandle(e.target.value);
                if (igError) setIgError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') void saveInstagram();
              }}
            />
          </div>
          {igError && (
            <p className="p-dialog-error" role="alert">
              {igError}
            </p>
          )}
        </Modal>
      )}

      {/* ── Restore: name prompt ── */}
      {dialog?.kind === 'restore-name' && (
        <Modal
          title="Restore old library"
          onClose={() => setDialog(null)}
          actions={
            <div className="p-actions">
              <button type="button" className="p-btn p-btn-text" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button type="button" className="p-btn p-btn-filled" onClick={submitRestoreName}>
                Restore
              </button>
            </div>
          }
        >
          <p className="p-dialog-copy">
            Enter the name you used in the old version of Cachy. The cards saved under it will
            move into this account.
          </p>
          <input
            className="input"
            autoFocus
            autoCapitalize="words"
            placeholder="Your old name"
            value={restoreName}
            onChange={(e) => setRestoreName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') submitRestoreName();
            }}
            aria-label="Your old name"
          />
        </Modal>
      )}

      {/* ── Restore: confirm ── */}
      {dialog?.kind === 'restore-confirm' && (
        <Modal
          title="Restore your old library?"
          onClose={() => (restoreBusy ? undefined : setDialog(null))}
          actions={
            <div className="p-actions">
              <button
                type="button"
                className="p-btn p-btn-text"
                disabled={restoreBusy}
                onClick={() => setDialog(null)}
              >
                Not now
              </button>
              <button
                type="button"
                className="p-btn p-btn-filled"
                disabled={restoreBusy}
                onClick={() => void runClaim(dialog.name)}
              >
                {restoreBusy ? 'Restoring…' : 'Restore'}
              </button>
            </div>
          }
        >
          <p className="p-dialog-copy">
            Bring the cards you saved as &ldquo;{dialog.name}&rdquo; into this account.
          </p>
        </Modal>
      )}

      {/* ── Sign out ── */}
      {dialog?.kind === 'sign-out' && (
        <Modal
          title="Sign out?"
          onClose={() => setDialog(null)}
          actions={
            <div className="p-actions">
              <button type="button" className="p-btn p-btn-text" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="p-btn p-btn-filled danger"
                onClick={() => {
                  setDialog(null);
                  logout();
                  navigate('/login');
                }}
              >
                Sign out
              </button>
            </div>
          }
        >
          <p className="p-dialog-copy">
            Your name will be cleared and you&apos;ll be taken back to the setup screen. Your
            cards on the server are not affected.
          </p>
        </Modal>
      )}

      <div className="p-toast-host">{toastNode}</div>
    </div>
  );
}
