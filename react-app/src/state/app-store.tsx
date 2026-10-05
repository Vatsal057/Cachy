/**
 * App store — central state re-exports.
 *
 * Wraps the auth context and normalizes its interface for App.tsx, which
 * expects a `status` string ('loading' | 'signedIn' | 'signedOut').
 */
import type { ReactNode } from 'react';
import {
  AuthProvider as AuthCtxProvider,
  useAuth as useAuthCtx,
} from '../features/auth/AuthContext';

export function AppProvider({ children }: { children: ReactNode }) {
  return <AuthCtxProvider>{children}</AuthCtxProvider>;
}

type AuthStatus = 'loading' | 'signedIn' | 'signedOut';

interface NormalizedAuth {
  status: AuthStatus;
  user: string | null;
  token: string | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  register: (username: string, password: string) => Promise<string>;
  logout: () => void;
}

export function useAuth(): NormalizedAuth {
  const ctx = useAuthCtx();
  const status: AuthStatus = ctx.loading
    ? 'loading'
    : ctx.user
      ? 'signedIn'
      : 'signedOut';
  return { ...ctx, status };
}
