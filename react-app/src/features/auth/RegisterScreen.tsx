import { useState } from 'react';
import type { FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { apiErrorMessage } from '../../api/client';
import { useAuth } from './AuthContext';

export default function RegisterScreen() {
  const { register } = useAuth();
  const navigate = useNavigate();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  /** Recovery code shown exactly once after signup. */
  const [recoveryCode, setRecoveryCode] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setError(null);
    setBusy(true);
    try {
      const code = await register(username, password);
      setRecoveryCode(code);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  if (recoveryCode) {
    return (
      <main className="page auth-page">
        <p className="eyebrow">Cachy</p>
        <h1 className="display">Save this code</h1>
        <p className="muted">
          This recovery code is shown <strong>once</strong>. It is the only way to reset your password —
          store it somewhere safe.
        </p>
        <div className="card recovery-card">
          <code className="recovery-code">{recoveryCode}</code>
        </div>
        <button className="btn btn-block" onClick={() => navigate('/', { replace: true })}>
          I&apos;ve saved it — open my library
        </button>
      </main>
    );
  }

  return (
    <main className="page auth-page">
      <p className="eyebrow">Cachy</p>
      <h1 className="display">Create your ID</h1>
      <p className="muted">Lowercase letters, numbers and underscores, 3–20 characters.</p>

      {error && (
        <div className="banner banner-error" role="alert">
          {error}
        </div>
      )}

      <form className="form" onSubmit={submit}>
        <label className="field">
          <span className="field-label">Username</span>
          <input
            className="input"
            type="text"
            autoCapitalize="none"
            autoCorrect="off"
            autoComplete="username"
            placeholder="your_cachy_id"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
          />
        </label>
        <label className="field">
          <span className="field-label">Password</span>
          <input
            className="input"
            type="password"
            autoComplete="new-password"
            placeholder="••••••••"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        <button className="btn btn-block" type="submit" disabled={busy}>
          {busy ? 'Creating…' : 'Create ID'}
        </button>
      </form>

      <p className="muted auth-switch">
        Already have one? <Link to="/login">Sign in</Link>
      </p>
    </main>
  );
}
