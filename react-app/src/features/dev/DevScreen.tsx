/**
 * Developer — port of Flutter's `_DeveloperScreen` (profile_screen.dart).
 *
 * Reached only through the version-tap gate on the profile screen: 7 taps
 * on the Version row → "Developer access" password dialog → 'vatxzz' →
 * the profile screen sets DEV_UNLOCK_KEY in sessionStorage and navigates
 * to /dev. This screen redirects to /profile when the flag is missing.
 *
 * The gate is client-side only — same as the Flutter app, whose source
 * notes the password is extractable from the bundle: it hides these
 * controls from casual users, it is not real security.
 *
 * Server controls are live: "Configure server URL" persists the override in
 * localStorage (`cachy_api_base`, read by the ApiClient on startup) and
 * applies it immediately via `api.setBaseUrl`; "Reset to default backend"
 * clears it. Two Flutter controls have no web equivalent and are shown as
 * honest disabled rows — LAN discovery (browsers have no raw UDP) and the
 * on-device model toggle (no local model can run in a browser).
 */
import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import {
  ArrowCounterClockwise,
  Broadcast,
  CaretLeft,
  CaretRight,
  Cpu,
  HardDrives,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import type { ReactNode } from 'react';
import { API_BASE_STORAGE_KEY, DEFAULT_BASE_URL, api } from '../../api/client';
import { Modal, useToast } from '../../ui/feedback';
import './dev.css';

/**
 * Session flag set by the profile screen's developer gate on a correct
 * password. Cleared when the tab closes (sessionStorage).
 */
export const DEV_UNLOCK_KEY = 'cachy_dev_unlocked';

function isUnlocked(): boolean {
  try {
    return sessionStorage.getItem(DEV_UNLOCK_KEY) === '1';
  } catch {
    return false; // private mode — the gate can't persist
  }
}

function Section({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section className="d-section">
      <h2 className="d-section-label">{label}</h2>
      {children}
    </section>
  );
}

function Tile({
  icon: Leading,
  title,
  sub,
  note,
  mono,
  disabled,
  onClick,
}: {
  icon: Icon;
  title: string;
  sub: string;
  /** Extra honest-copy line for rows that can't work on web. */
  note?: string;
  /** Render the subtitle in the mono face (URLs). */
  mono?: boolean;
  disabled?: boolean;
  onClick?: () => void;
}) {
  const content = (
    <>
      <span className="d-tile-icon" aria-hidden>
        <Leading size={22} />
      </span>
      <span className="d-tile-body">
        <span className="d-tile-title">{title}</span>
        <span className={`d-tile-sub${mono ? ' mono' : ''}`}>{sub}</span>
        {note ? <span className="d-tile-note">{note}</span> : null}
      </span>
      {onClick ? <CaretRight size={18} className="d-tile-chevron" aria-hidden /> : null}
    </>
  );
  if (onClick) {
    return (
      <button type="button" className="d-tile tappable" onClick={onClick}>
        {content}
      </button>
    );
  }
  return (
    <div
      className={`d-tile${disabled ? ' disabled' : ''}`}
      aria-disabled={disabled ? 'true' : undefined}
    >
      {content}
    </div>
  );
}

/** Returns the cleaned URL, or an error message. Trailing slashes dropped. */
function parseBackendUrl(raw: string): { url: string } | { error: string } {
  const trimmed = raw.trim();
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { error: 'Enter a full URL, e.g. http://192.168.1.5:8000' };
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return { error: 'The URL must start with http:// or https://' };
  }
  return { url: trimmed.replace(/\/+$/, '') };
}

export default function DevScreen() {
  const navigate = useNavigate();
  const { showToast, toastNode } = useToast();
  const [unlocked] = useState(isUnlocked);
  const [baseUrl, setBaseUrl] = useState(() => api.getBaseUrl());
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const [draftError, setDraftError] = useState<string | null>(null);

  if (!unlocked) {
    return <Navigate to="/profile" replace />;
  }

  function applyUrl(url: string, persist: boolean) {
    try {
      if (persist) localStorage.setItem(API_BASE_STORAGE_KEY, url);
      else localStorage.removeItem(API_BASE_STORAGE_KEY);
    } catch {
      /* private mode — the override lasts for this session only */
    }
    api.setBaseUrl(url);
    setBaseUrl(api.getBaseUrl());
    showToast(`Backend set to ${url || '(same origin)'}`);
  }

  function openEditor() {
    setDraft(baseUrl);
    setDraftError(null);
    setEditing(true);
  }

  function saveDraft() {
    // Flutter ignores an empty value.
    if (!draft.trim()) {
      setEditing(false);
      return;
    }
    const parsed = parseBackendUrl(draft);
    if ('error' in parsed) {
      setDraftError(parsed.error);
      return;
    }
    setEditing(false);
    applyUrl(parsed.url, parsed.url !== DEFAULT_BASE_URL);
  }

  const mixedContentRisk =
    window.location.protocol === 'https:' && /^http:\/\//i.test(draft.trim());

  return (
    <div className="page">
      <div className="dev-topbar">
        <button
          type="button"
          className="back-btn"
          onClick={() => navigate('/profile')}
        >
          <CaretLeft size={16} />
          You
        </button>
      </div>

      <h1 className="dev-title">Developer</h1>

      <Section label="Server">
        <Tile
          icon={HardDrives}
          title="Active server endpoint"
          sub={baseUrl || '(same origin)'}
          mono
          onClick={openEditor}
        />
        <Tile
          icon={Broadcast}
          title="Discover LAN server"
          sub="LAN discovery needs raw network access, which browsers don't allow."
          disabled
        />
        <Tile
          icon={ArrowCounterClockwise}
          title="Reset to default backend"
          sub="Clear the override and reconnect to the hosted Space."
          onClick={() => applyUrl(DEFAULT_BASE_URL, false)}
        />
      </Section>

      <Section label="AI model">
        <div className="d-toggle-tile disabled" aria-disabled="true">
          <span className="d-tile-icon" aria-hidden>
            <Cpu size={22} />
          </span>
          <span className="d-tile-body">
            <span className="d-tile-title">Use on-device model</span>
            <span className="d-tile-sub">
              On-device models can&apos;t run in a browser — cards are always
              structured with the server LLM.
            </span>
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={false}
            aria-disabled="true"
            disabled
            tabIndex={-1}
            className="d-switch"
            aria-label="Use on-device model"
          >
            <span className="d-switch-thumb" aria-hidden />
          </button>
        </div>
      </Section>

      <p className="d-footnote">
        Changes take effect immediately and persist across launches. Your
        sign-in only works on the server that issued it, so sign in again after
        pointing the app at a different backend.
      </p>

      {editing && (
        <Modal
          title="Configure server URL"
          onClose={() => setEditing(false)}
          actions={
            <div className="d-actions">
              <button type="button" className="d-btn d-btn-text" onClick={() => setEditing(false)}>
                Cancel
              </button>
              <button type="button" className="d-btn d-btn-filled" onClick={saveDraft}>
                Save
              </button>
            </div>
          }
        >
          <label className="d-field-label" htmlFor="backend-url">
            Backend URL
          </label>
          <input
            id="backend-url"
            className="input"
            type="url"
            inputMode="url"
            autoFocus
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            placeholder="http://192.168.1.5:8000"
            value={draft}
            aria-invalid={draftError ? true : undefined}
            onChange={(e) => {
              setDraft(e.target.value);
              if (draftError) setDraftError(null);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') saveDraft();
            }}
          />
          {draftError ? (
            <p className="d-dialog-error" role="alert">
              {draftError}
            </p>
          ) : mixedContentRisk ? (
            <p className="d-dialog-hint">
              This page is served over https, so browsers will block an http://
              backend (except localhost).
            </p>
          ) : null}
        </Modal>
      )}

      <div className="d-toast-host">{toastNode}</div>
    </div>
  );
}
