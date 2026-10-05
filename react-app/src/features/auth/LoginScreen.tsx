import { useState } from 'react';
import type { FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { apiErrorMessage } from '../../api/client';
import { useAuth } from './AuthContext';

export default function LoginScreen() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setError(null);
    setBusy(true);
    try {
      await login(username, password);
      navigate('/', { replace: true });
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="page auth-page">
      <p className="eyebrow">Cachy</p>
      <h1 className="display">Sign in</h1>
      <p className="muted">Use your Cachy ID to open your library.</p>

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
            autoComplete="current-password"
            placeholder="••••••••"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        <button className="btn btn-block" type="submit" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>

      <p className="muted auth-switch">
        New here? <Link to="/register">Create a Cachy ID</Link>
      </p>
    </main>
  );
}
