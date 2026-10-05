import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { api, ApiException } from '../../api/client';

const TOKEN_KEY = 'cachy_id_token';
const USERNAME_KEY = 'cachy_id_username';

interface AuthContextValue {
  /** Cachy ID username, or null when signed out. */
  user: string | null;
  token: string | null;
  /** True while restoring a persisted session on launch. */
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  /** Registers and returns the one-time recovery code (caller must display it). */
  register: (username: string, password: string) => Promise<string>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<string | null>(() => {
    try {
      return localStorage.getItem(USERNAME_KEY);
    } catch {
      return null;
    }
  });
  const [token, setToken] = useState<string | null>(() => {
    try {
      return localStorage.getItem(TOKEN_KEY);
    } catch {
      return null;
    }
  });
  const [loading, setLoading] = useState(true);

  // Keep the API client's token provider in sync with auth state.
  useEffect(() => {
    api.setTokenProvider(() => {
      try {
        return localStorage.getItem(TOKEN_KEY);
      } catch {
        return null;
      }
    });
  }, []);

  // Validate any persisted token on launch; drop it if the server rejects it.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const stored = (() => {
        try {
          return localStorage.getItem(TOKEN_KEY);
        } catch {
          return null;
        }
      })();
      if (!stored) {
        setLoading(false);
        return;
      }
      try {
        const me = await api.idMe();
        if (!cancelled) {
          setUser(me.username);
          try {
            if (me.username) localStorage.setItem(USERNAME_KEY, me.username);
          } catch {
            /* storage unavailable — session still works in memory */
          }
        }
      } catch (err) {
        if (!cancelled && err instanceof ApiException && (err.status === 401 || err.status === 403)) {
          try {
            localStorage.removeItem(TOKEN_KEY);
            localStorage.removeItem(USERNAME_KEY);
          } catch {
            /* ignore */
          }
          setToken(null);
          setUser(null);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const persist = useCallback((nextToken: string, username: string) => {
    try {
      localStorage.setItem(TOKEN_KEY, nextToken);
      localStorage.setItem(USERNAME_KEY, username);
    } catch {
      /* private mode — session works until reload */
    }
    setToken(nextToken);
    setUser(username);
  }, []);

  const login = useCallback(
    async (username: string, password: string) => {
      const res = await api.idLogin(username.trim(), password);
      persist(res.token, res.username);
    },
    [persist],
  );

  const register = useCallback(
    async (username: string, password: string) => {
      const res = await api.idRegister(username.trim(), password);
      persist(res.token, res.username);
      return res.recovery_code;
    },
    [persist],
  );

  const logout = useCallback(() => {
    try {
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(USERNAME_KEY);
    } catch {
      /* ignore */
    }
    setToken(null);
    setUser(null);
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({ user, token, loading, login, register, logout }),
    [user, token, loading, login, register, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
