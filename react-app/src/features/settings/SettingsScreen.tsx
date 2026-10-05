/**
 * Settings — minimal screen stub.
 *
 * The route exists in App.tsx ("/settings"); this stub keeps the import
 * resolving until the full settings UI is ported from the Flutter app.
 */
import { Link } from 'react-router-dom';
import { ArrowLeft } from 'phosphor-react';

export default function SettingsScreen() {
  return (
    <main className="page">
      <div className="page-head">
        <Link to="/profile" className="back-btn" aria-label="Back to profile">
          <ArrowLeft size={20} weight="regular" />
        </Link>
        <h1 className="page-title">Settings</h1>
      </div>
      <div className="stack">
        <div className="empty-state">
          <p className="muted">Settings are coming soon.</p>
        </div>
      </div>
    </main>
  );
}
