/**
 * App shell — port of Flutter's ui/core/home_shell.dart + root_gate.dart.
 *
 * Navigation spec (from home_shell.dart):
 *   Tabs (order): HOME → / ; FOLDERS → /collections ; TO-DO → /actions ;
 *     FEED → /feed ; YOU → /profile
 *     (phosphor: House, Folder, ListChecks, Cards, User — regular when
 *     inactive, fill when active)
 *   Mobile (< 600px): floating glass pill nav — 64px high, radius 99,
 *     20px side margins, bottom = safe-area + 12px, blur 20, 0.8px
 *     glassBorder, icon 22px with scale(1.10) when active, 9px mono labels
 *     (w700 active / w500 inactive, letter-spacing 0.07em).
 *   Desktop (>= 600px): glass side rail — 72px wide (64px compact when
 *     height < 520px; 180px extended when width >= 1100px), capture button
 *     leading (56px accent circle, hover scale 1.08), accent-10% pill
 *     indicator, labels only on the selected tab (10px mono), capture FAB
 *     becomes a mobile-only floating button.
 *   The reader hides chrome via its own layout; LaunchGate fades the app
 *   in over 550ms once the auth gate resolves (root_gate.dart).
 *
 * Route table: / (library, cards tab), /library, /library/chat,
 *   /collections, /collections/:id, /capture, /actions, /feed, /connections,
 *   /concepts (library, concepts tab), /concepts/:id, /catalog (library,
 *   catalog tab), /graph, /search, /profile, /settings, /dev, /reader/:id,
 *   /reader/:id/chat, /reader/:id/rabbithole, /shared/:token ("Save to my
 *   Cachy"), /login, /register; unknown paths redirect to /. This file only
 *   owns the shell visuals.
 *
 * Keyboard (home_shell.dart CallbackShortcuts): ⌘/Ctrl+N opens capture,
 *   ⌘/Ctrl+1..5 jump to the five tabs.
 */
import { useCallback, useEffect, useState } from 'react';
import {
  Navigate,
  NavLink,
  Route,
  Routes,
  useLocation,
  useNavigate,
} from 'react-router-dom';
import {
  Cards,
  Folder,
  House,
  ListChecks,
  Plus,
  User,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { AppProvider } from './state/app-store';
import { useAuth } from './state/app-store';
import type { ConnectionItem } from './api/types';
import { useMedia } from './ui/use-media';
import { AmbientBackground } from './ui/glass';
import './ui/widgets.css';

import LoginScreen from './features/auth/LoginScreen';
import RegisterScreen from './features/auth/RegisterScreen';
import SplashScreen from './features/onboarding/SplashScreen';
import OnboardingScreen from './features/onboarding/OnboardingScreen';
import CardChatScreen from './features/chat/CardChatScreen';
import LibraryChatScreen from './features/chat/LibraryChatScreen';
import RabbitHoleScreen from './features/rabbithole/RabbitHoleScreen';
import CollectionDetailScreen from './features/collections/CollectionDetailScreen';
import SharedCardScreen from './features/share/SharedCardScreen';
import LibraryScreen from './features/library/LibraryScreen';
import CollectionsScreen from './features/collections/CollectionsScreen';
import ReaderScreen from './features/reader/ReaderScreen';
import GraphScreen from './features/graph/GraphScreen';
import ConceptDetailScreen from './features/concepts/ConceptDetailScreen';
import CaptureScreen from './features/capture/CaptureScreen';
import ActionsScreen from './features/actions/ActionsScreen';
import FeedScreen from './features/feed/FeedScreen';
import ConnectionsScreen from './features/feed/ConnectionsScreen';
import ProfileScreen from './features/profile/ProfileScreen';
import SettingsScreen from './features/settings/SettingsScreen';
import DevScreen from './features/dev/DevScreen';
import SearchScreen from './features/search/SearchScreen';

interface TabDef {
  to: string;
  label: string;
  Icon: Icon;
}

const NAV_TABS: TabDef[] = [
  { to: '/', label: 'Home', Icon: House },
  { to: '/collections', label: 'Folders', Icon: Folder },
  { to: '/actions', label: 'To-Do', Icon: ListChecks },
  { to: '/feed', label: 'Feed', Icon: Cards },
  { to: '/profile', label: 'You', Icon: User },
];

/* ── Launch gate: splash → onboarding → auth → app (root_gate.dart) ── */

const SEEN_ONBOARDING_KEY = 'cachy_seen_onboarding';
/** Deep link (e.g. /shared/:token) to resume once the user has signed in. */
const POST_LOGIN_KEY = 'cachy_post_login';

function readSeenOnboarding(): boolean {
  try {
    return localStorage.getItem(SEEN_ONBOARDING_KEY) === '1';
  } catch {
    return true; // storage unavailable — don't trap the user in onboarding
  }
}

function LaunchGate() {
  const { status, user } = useAuth();
  const location = useLocation();
  const [splashDone, setSplashDone] = useState(false);
  const [seenOnboarding, setSeenOnboarding] = useState(readSeenOnboarding);

  useEffect(() => {
    const t = window.setTimeout(() => setSplashDone(true), 1300);
    return () => window.clearTimeout(t);
  }, []);

  // Remember a share link opened while signed out so it survives the login.
  const signedOut = status === 'signedOut' || (status !== 'loading' && !user);
  useEffect(() => {
    if (!signedOut) return;
    if (location.pathname.startsWith('/shared/')) {
      try {
        sessionStorage.setItem(POST_LOGIN_KEY, location.pathname);
      } catch {
        /* ignore */
      }
    }
  }, [signedOut, location.pathname]);

  if (!splashDone) {
    return <SplashScreen onDone={() => setSplashDone(true)} />;
  }
  if (status === 'loading') {
    return <div className="app-shell" aria-label="Loading" />;
  }
  if (signedOut && !seenOnboarding) {
    return (
      <OnboardingScreen
        onDone={() => {
          try {
            localStorage.setItem(SEEN_ONBOARDING_KEY, '1');
          } catch {
            /* ignore */
          }
          setSeenOnboarding(true);
        }}
      />
    );
  }
  if (status === 'signedOut' || !user) {
    // Auth branch owns /login + /register so the screens' <Link>s and
    // navigate() calls land on real routes instead of falling through.
    return (
      <Routes>
        <Route path="/register" element={<RegisterScreen />} />
        <Route path="*" element={<LoginScreen />} />
      </Routes>
    );
  }
  return (
    <div className="app-fade-in">
      <HomeShell />
    </div>
  );
}

/* ── Mobile floating glass pill nav (< 600px) ── */

function PillNav() {
  const location = useLocation();
  return (
    <nav className="pill-nav" aria-label="Primary">
      {NAV_TABS.map(({ to, label, Icon }) => {
        const active =
          to === '/'
            ? location.pathname === '/'
            : location.pathname.startsWith(to);
        return (
          <NavLink
            key={to}
            to={to}
            className={`pill-tab${active ? ' active' : ''}`}
            aria-current={active ? 'page' : undefined}
          >
            <span className="pill-icon">
              <Icon size={22} weight={active ? 'fill' : 'regular'} />
            </span>
            <span className="pill-label">{label.toUpperCase()}</span>
          </NavLink>
        );
      })}
    </nav>
  );
}

/* ── Desktop glass side rail (>= 600px) ── */

function SideRail() {
  const location = useLocation();
  const navigate = useNavigate();
  const compact = useMedia('(max-height: 519px)');
  const extended = useMedia('(min-width: 1100px)');

  return (
    <nav
      className={`side-rail${compact ? ' compact' : ''}${
        extended ? ' extended' : ''
      }`}
      aria-label="Primary"
    >
      <button
        type="button"
        className="capture-btn"
        title="New capture (⌘N)"
        aria-label="New capture"
        onClick={() => navigate('/capture')}
      >
        <Plus size={24} weight="bold" />
      </button>
      {NAV_TABS.map(({ to, label, Icon }) => {
        const active =
          to === '/'
            ? location.pathname === '/'
            : location.pathname.startsWith(to);
        return (
          <NavLink
            key={to}
            to={to}
            className={`rail-tab${active ? ' active' : ''}`}
            aria-current={active ? 'page' : undefined}
          >
            {active ? <span className="rail-indicator" aria-hidden /> : null}
            <span className="rail-icon">
              <Icon size={22} weight={active ? 'fill' : 'regular'} />
            </span>
            <span className="rail-label">{label.toUpperCase()}</span>
          </NavLink>
        );
      })}
      <span className="rail-spacer" />
    </nav>
  );
}

/* ── Shell ── */

function HomeShell() {
  const location = useLocation();
  const navigate = useNavigate();
  const desktop = useMedia('(min-width: 600px)');
  const onReader = location.pathname.startsWith('/reader');

  // Resume a share link that was opened before sign-in.
  useEffect(() => {
    try {
      const pending = sessionStorage.getItem(POST_LOGIN_KEY);
      if (pending) {
        sessionStorage.removeItem(POST_LOGIN_KEY);
        navigate(pending, { replace: true });
      }
    } catch {
      /* ignore */
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ⌘/Ctrl+N → capture; ⌘/Ctrl+1..5 → tabs (home_shell.dart CallbackShortcuts).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || e.altKey || e.shiftKey) return;
      const t = e.target as HTMLElement | null;
      const typing =
        !!t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
      if (e.key === 'n' || e.key === 'N') {
        if (typing) return;
        e.preventDefault();
        navigate('/capture');
        return;
      }
      const n = Number(e.key);
      if (Number.isInteger(n) && n >= 1 && n <= NAV_TABS.length) {
        e.preventDefault();
        navigate(NAV_TABS[n - 1].to);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [navigate]);

  return (
    <div className="app-shell">
      <AmbientBackground />
      <div className="shell-main">
        <Routes>
          {/* Library tabs — one screen, initial tab from the route. */}
          <Route path="/" element={<LibraryScreen initialTab="cards" />} />
          <Route path="/concepts" element={<LibraryScreen initialTab="concepts" />} />
          <Route path="/concepts/:id" element={<ConceptDetailScreen />} />
          <Route path="/catalog" element={<LibraryScreen initialTab="catalog" />} />
          <Route path="/library" element={<LibraryScreen />} />
          <Route path="/library/chat" element={<LibraryChatScreen />} />
          <Route path="/collections" element={<CollectionsScreen />} />
          <Route path="/collections/:id" element={<CollectionDetailScreen />} />
          <Route path="/capture" element={<CaptureScreen />} />
          <Route path="/actions" element={<ActionsScreen />} />
          <Route path="/feed" element={<FeedScreen />} />
          <Route path="/connections" element={<ConnectionsRoute />} />
          <Route path="/profile" element={<ProfileScreen />} />
          <Route path="/settings" element={<SettingsScreen />} />
          <Route path="/dev" element={<DevScreen />} />
          <Route path="/reader/:id" element={<ReaderScreen />} />
          <Route path="/reader/:id/chat" element={<CardChatScreen />} />
          <Route path="/reader/:id/rabbithole" element={<RabbitHoleScreen />} />
          <Route path="/shared/:token" element={<SharedCardScreen />} />
          <Route path="/graph" element={<GraphScreen />} />
          <Route path="/search" element={<SearchScreen />} />
          <Route path="/login" element={<LoginScreen />} />
          <Route path="/register" element={<RegisterScreen />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </div>
      {!onReader ? (
        desktop ? (
          <SideRail />
        ) : (
          <>
            <PillNav />
            <button
              type="button"
              className="capture-fab"
              aria-label="New capture"
              onClick={() => navigate('/capture')}
            >
              <Plus size={24} weight="bold" />
            </button>
          </>
        )
      ) : null}
    </div>
  );
}

/**
 * /connections: feeds ConnectionsScreen with the backend's connection
 * pairs (GET /connections). The screen itself is props-driven; this wrapper
 * is the data seam. `onFindMore` refreshes (spends a little LLM budget for
 * new links), `onRetry` re-fetches the cache.
 */
function ConnectionsRoute() {
  const [items, setItems] = useState<ConnectionItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (refresh: boolean) => {
    if (refresh) setRefreshing(true);
    else setLoading(true);
    setError(null);
    try {
      const { api } = await import('./api/client');
      const res = await api.connections(20, refresh);
      setItems(res);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void load(false);
  }, [load]);

  return (
    <ConnectionsScreen
      connections={items.map((c) => ({
        cardA: c.card_a,
        cardB: c.card_b,
        blurb: c.blurb,
      }))}
      loading={loading}
      refreshing={refreshing}
      error={error}
      onFindMore={() => void load(true)}
      onRetry={() => void load(false)}
    />
  );
}

export default function App() {
  return (
    <AppProvider>
      <LaunchGate />
    </AppProvider>
  );
}

export { HomeShell };
