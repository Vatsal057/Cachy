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
 * Web notes: every Flutter control on this screen is a manual
 * server-connection override, which has no web equivalent —
 *   - the React ApiClient ships with a fixed baseUrl
 *     (https://vatxzz-cachy.hf.space) and exposes no updateBaseUrl, and
 *     changing src/api is out of scope for this port;
 *   - a browser page cannot scan the LAN for a backend;
 *   - on-device AI models (Gemma) cannot run in a browser.
 * So the server rows are display-only / disabled with explanatory copy,
 * "Reset to default backend" is omitted (nothing can be overridden, so
 * there is nothing to reset), and the on-device-model toggle renders off
 * + disabled. Nothing here is fake: no control pretends to do something
 * it doesn't.
 */
import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Broadcast, CaretLeft, Cpu, HardDrives } from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import type { ReactNode } from 'react';
import './dev.css';

/**
 * Session flag set by the profile screen's developer gate on a correct
 * password. Cleared when the tab closes (sessionStorage).
 */
export const DEV_UNLOCK_KEY = 'cachy_dev_unlocked';

/** The backend the React web client is built against (api/client.ts). */
const FIXED_BACKEND_URL = 'https://vatxzz-cachy.hf.space';

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
  disabled,
}: {
  icon: Icon;
  title: string;
  sub: string;
  /** Extra honest-copy line for rows that can't work on web. */
  note?: string;
  disabled?: boolean;
}) {
  return (
    <div
      className={`d-tile${disabled ? ' disabled' : ''}`}
      aria-disabled={disabled ? 'true' : undefined}
    >
      <span className="d-tile-icon" aria-hidden>
        <Leading size={22} />
      </span>
      <span className="d-tile-body">
        <span className="d-tile-title">{title}</span>
        <span className="d-tile-sub mono">{sub}</span>
        {note ? <span className="d-tile-note">{note}</span> : null}
      </span>
    </div>
  );
}

export default function DevScreen() {
  const navigate = useNavigate();
  const [unlocked] = useState(isUnlocked);

  if (!unlocked) {
    return <Navigate to="/profile" replace />;
  }

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
          sub={FIXED_BACKEND_URL}
          note="The web client is built against this backend — editing the server isn't available here."
        />
        <Tile
          icon={Broadcast}
          title="Discover LAN server"
          sub="LAN discovery needs raw network access, which browsers don't allow."
          disabled
        />
        {/* "Reset to default backend" omitted: with no editable override on
            web there is nothing to reset; a disabled row would only confuse. */}
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
        Server controls aren&apos;t available in the web app — it always talks
        to the hosted backend.
      </p>
    </div>
  );
}
