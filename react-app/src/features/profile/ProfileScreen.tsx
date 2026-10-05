/**
 * Profile ("You") — port of profile_screen.dart.
 * Shelf header + stat strip, then Appearance / Library / About / Account
 * sections with the Flutter copy, dialogs and toasts intact.
 *
 * Web notes: Google account rows, the backup banner and "Claim a Cachy ID"
 * are N/A (web auth is Cachy-ID-only and the route requires a session);
 * Instagram linking, legacy restore and vault export have no web backend
 * yet, so their actions say so honestly instead of pretending.
 */
import { useEffect, useState } from 'react';
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
import { api } from '../../api/client';
import type { Card, QuotaStatus } from '../../api/types';
import { useAuth } from '../auth/AuthContext';
import { Modal, useToast } from '../../ui/feedback';
import { DEV_UNLOCK_KEY } from '../dev/DevScreen';
import './profile.css';

/* ------------------------------------------------------------------ */
/* Theme — SegmentedButton parity via data-theme (index.css honors     */
/* [data-theme='light']; dark is the default).                         */
/* ------------------------------------------------------------------ */

type ThemeMode = 'system' | 'light' | 'dark';
const THEME_KEY = 'cachy_theme';

function readTheme(): ThemeMode {
  try {
    const v = localStorage.getItem(THEME_KEY);
    return v === 'light' || v === 'dark' ? v : 'system';
  } catch {
    return 'system';
  }
}

function applyTheme(mode: ThemeMode) {
  const dark =
    mode === 'dark' ||
    (mode === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
}

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

const NOT_ON_WEB = {
  vaultExport: "Vault export isn't available in the web app yet.",
  instagramLink: "Instagram linking isn't available in the web app yet.",
  libraryRestore: "Library restore isn't available in the web app yet.",
};

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
  const [quota, setQuota] = useState<QuotaStatus | null>(null);
  const [quotaFailed, setQuotaFailed] = useState(false);
  const [dialog, setDialog] = useState<DialogState>(null);
  const [devPassword, setDevPassword] = useState('');
  const [igHandle, setIgHandle] = useState('');
  const [restoreName, setRestoreName] = useState('');
  const [versionTaps, setVersionTaps] = useState(0);

  /* Theme */
  useEffect(() => {
    applyTheme(themeMode);
    try {
      localStorage.setItem(THEME_KEY, themeMode);
    } catch {
      /* private mode — applies for this session */
    }
  }, [themeMode]);
  useEffect(() => {
    if (themeMode !== 'system') return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => applyTheme('system');
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
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
            return t >= weekAgo;
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
      try {
        let total = 0;
        for (let offset = 0; offset < 5000; offset += 200) {
          const page = await api.listCatalog({ limit: 200, offset });
          total += page.length;
          if (page.length < 200) break;
        }
        if (alive) setRefCount(total);
      } catch {
        /* References stays '—' on error, like the Flutter FutureBuilder */
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

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

  const igLinked: string | null = null; // no link backend on web yet

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
          title="Export as Obsidian vault"
          sub="Saves every card as a markdown note, zipped to open in Obsidian."
          onClick={() => showToast(NOT_ON_WEB.vaultExport)}
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
          onClick={() => {
            setIgHandle(igLinked ? `@${igLinked}` : '');
            setDialog({ kind: 'instagram' });
          }}
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
            <>
              <button type="button" className="fb-text-btn" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="fb-filled-btn"
                onClick={() => {
                  setDialog(null);
                  showToast('Nothing cached yet');
                }}
              >
                Clear
              </button>
            </>
          }
        >
          <p className="p-dialog-copy">Removes locally saved cards. They re-download when opened.</p>
        </Modal>
      )}

      {/* ── Developer gate ── */}
      {dialog?.kind === 'dev' && (
        <Modal
          title="Developer access"
          onClose={() => setDialog(null)}
          actions={
            <>
              <button type="button" className="fb-text-btn" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button type="button" className="fb-filled-btn" onClick={unlockDev}>
                Unlock
              </button>
            </>
          }
        >
          <label className="fb-field-label" htmlFor="dev-password">
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
            <>
              {igLinked && (
                <button
                  type="button"
                  className="fb-text-btn danger"
                  onClick={() => {
                    setDialog(null);
                    showToast(NOT_ON_WEB.instagramLink);
                  }}
                >
                  Unlink
                </button>
              )}
              <button type="button" className="fb-text-btn" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="fb-filled-btn"
                onClick={() => {
                  setDialog(null);
                  showToast(NOT_ON_WEB.instagramLink);
                }}
              >
                Save
              </button>
            </>
          }
        >
          <p className="p-dialog-copy">
            Link your Instagram username. Once linked, any reel you DM or share to @cachyapp
            will automatically appear on your Cachy shelf.
          </p>
          <label className="fb-field-label" htmlFor="ig-handle">
            Instagram username
          </label>
          <div className="fb-input-wrap">
            <At size={18} aria-hidden />
            <input
              id="ig-handle"
              className="input"
              autoFocus
              placeholder="@username"
              value={igHandle}
              onChange={(e) => setIgHandle(e.target.value)}
            />
          </div>
        </Modal>
      )}

      {/* ── Restore: name prompt ── */}
      {dialog?.kind === 'restore-name' && (
        <Modal
          title="Restore old library"
          onClose={() => setDialog(null)}
          actions={
            <>
              <button type="button" className="fb-text-btn" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="fb-filled-btn"
                onClick={() => {
                  const name = restoreName.trim();
                  if (!name) {
                    setDialog(null);
                    return;
                  }
                  setDialog({ kind: 'restore-confirm', name });
                }}
              >
                Restore
              </button>
            </>
          }
        >
          <p className="p-dialog-copy">
            Enter the name you used in the old version of Cachy. The cards saved under it will
            move into this account.
          </p>
          <input
            className="input"
            autoFocus
            placeholder="Your old name"
            value={restoreName}
            onChange={(e) => setRestoreName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                const name = restoreName.trim();
                setDialog(name ? { kind: 'restore-confirm', name } : null);
              }
            }}
            aria-label="Your old name"
          />
        </Modal>
      )}

      {/* ── Restore: confirm ── */}
      {dialog?.kind === 'restore-confirm' && (
        <Modal
          title="Restore your old library?"
          onClose={() => setDialog(null)}
          actions={
            <>
              <button type="button" className="fb-text-btn" onClick={() => setDialog(null)}>
                Not now
              </button>
              <button
                type="button"
                className="fb-filled-btn"
                onClick={() => {
                  setDialog(null);
                  showToast(NOT_ON_WEB.libraryRestore);
                }}
              >
                Restore
              </button>
            </>
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
            <>
              <button type="button" className="fb-text-btn" onClick={() => setDialog(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="fb-filled-btn danger"
                onClick={() => {
                  setDialog(null);
                  logout();
                  navigate('/login');
                }}
              >
                Sign out
              </button>
            </>
          }
        >
          <p className="p-dialog-copy">
            Your name will be cleared and you&apos;ll be taken back to the setup screen. Your
            cards on the server are not affected.
          </p>
        </Modal>
      )}

      {toastNode}
    </div>
  );
}
