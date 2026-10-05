import type {
  ActionItem,
  ActionItems,
  Artifact,
  Card,
  CardState,
  Collection,
  Concept,
  ConnectionItem,
  ContentType,
  CreateCardResponse,
  FeedItem,
  GraphData,
  IdAuthResult,
  IdMeResult,
  IdRegisterResult,
  QuotaStatus,
  ShareLink,
  SharedCardSaveResult,
  UsernameAvailableResult,
} from './types';

/** Friendly error surfaced to the UI. `detail` is the raw server message. */
export class ApiException extends Error {
  readonly status: number;
  readonly detail: string;

  constructor(status: number, detail: string) {
    super(detail || `Request failed (${status})`);
    this.name = 'ApiException';
    this.status = status;
    this.detail = detail;
  }

  /** Human-readable message safe to show in the UI. */
  get friendlyMessage(): string {
    if (this.status === 401 || this.status === 403) {
      return 'Session expired — please sign in again.';
    }
    if (this.status === 404) {
      return 'That card is gone.';
    }
    if (this.status === 409) {
      return this.detail || 'Already exists.';
    }
    if (this.status === 422) {
      return this.detail || 'Invalid input — check your entries.';
    }
    if (this.status === 429) {
      return 'Daily quota reached — try again tomorrow.';
    }
    if (this.status >= 500) {
      return 'Server error — please try again in a bit.';
    }
    return this.detail || 'Something went wrong.';
  }
}

type TokenProvider = () => string | null;

interface RequestOptions {
  method?: string;
  body?: unknown;
  /** Skip attaching the auth header (public endpoints). */
  public?: boolean;
  query?: Record<string, string | number | boolean | undefined | null>;
}

const DEFAULT_BASE_URL = 'https://vatxzz-cachy.hf.space';

/** Default TTL for the in-memory GET cache (60s). */
const DEFAULT_CACHE_TTL_MS = 60_000;

/** Per-method cache override — trailing arg of the cached GET methods. */
export interface CacheOptions {
  /** Cache TTL in ms. Defaults to 60s. */
  ttlMs?: number;
}

interface CacheEntry {
  data: unknown;
  expiresAt: number;
}

/**
 * Memoized media URL resolutions, module-level so every caller shares it.
 * Token-aware: entries are re-resolved when the auth token changes.
 */
const mediaUrlCache = new Map<string, { token: string | null; url: string }>();

/**
 * Stable cache-key fragment from query params. Only defined, non-empty
 * values participate, in sorted key order, so equivalent calls map to the
 * same key regardless of argument order.
 */
function cacheQueryFragment(params: Record<string, unknown> | undefined): string {
  if (!params) return '';
  return Object.keys(params)
    .sort()
    .filter((k) => {
      const v = params[k];
      return v !== undefined && v !== null && v !== '';
    })
    .map((k) => `${k}=${String(params[k])}`)
    .join('&');
}

export class ApiClient {
  private baseUrl: string;
  private tokenProvider: TokenProvider = () => null;
  private lastToken: string | null = null;
  /** In-memory TTL cache for idempotent GETs. */
  private cache = new Map<string, CacheEntry>();
  /** In-flight GETs by cache key — identical concurrent calls share one promise. */
  private inflight = new Map<string, Promise<unknown>>();
  /**
   * Token the cache was populated under. When the auth identity changes
   * (sign-in/out/switch) the cache is dropped so one owner's data is never
   * served to another.
   */
  private cacheToken: string | null | undefined = undefined;

  constructor(baseUrl: string = DEFAULT_BASE_URL) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  /** Called before every authed request to fetch the current token. */
  setTokenProvider(fn: TokenProvider): void {
    this.tokenProvider = fn;
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url.replace(/\/$/, '');
    // Cached URLs and payloads belong to the previous host — drop them.
    this.cache.clear();
    this.inflight.clear();
    mediaUrlCache.clear();
  }

  mediaUrl(cardId: string, filename: string): string {
    return `${this.baseUrl}/media/${encodeURIComponent(cardId)}/${encodeURIComponent(filename)}`;
  }

  /**
   * Resolve a media reference to a fetchable URL. Mirrors Dart's resolveMedia.
   * Absolute URLs pass through; relative paths join onto baseUrl.
   * For the auth-gated /media/ proxy on web, append ?token= (backend's
   * get_owner_query_or_header accepts it; <img> can't send headers).
   * Token is base64url JWT — URL-safe, no encoding needed.
   *
   * Results are memoized per ref string (token-aware: a token change
   * re-resolves) so per-render-per-tile calls don't rebuild strings.
   */
  resolveMedia(ref: string): string {
    if (/^https?:\/\//i.test(ref)) return ref;
    const memo = mediaUrlCache.get(ref);
    if (memo && memo.token === this.lastToken) return memo.url;
    const path = ref.startsWith('/') ? ref : `/${ref}`;
    const url = `${this.baseUrl}${path}`;
    const resolved =
      path.startsWith('/media/') && this.lastToken ? `${url}?token=${this.lastToken}` : url;
    mediaUrlCache.set(ref, { token: this.lastToken, url: resolved });
    return resolved;
  }

  private async request<T>(path: string, opts: RequestOptions = {}): Promise<T> {
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (opts.body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }
    if (!opts.public) {
      const token = this.tokenProvider();
      // Auth identity changed (sign-in/out/switch) — cached data belongs to
      // the previous owner; drop it rather than serve it to the new one.
      if (this.cacheToken !== undefined && token !== this.cacheToken) {
        this.cache.clear();
        this.inflight.clear();
      }
      this.cacheToken = token;
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
        this.lastToken = token;
      }
    }

    let url = `${this.baseUrl}${path}`;
    if (opts.query) {
      const params = new URLSearchParams();
      for (const [k, v] of Object.entries(opts.query)) {
        if (v !== undefined && v !== null && v !== '') params.set(k, String(v));
      }
      const qs = params.toString();
      if (qs) url += `?${qs}`;
    }

    let res: Response;
    try {
      res = await fetch(url, {
        method: opts.method ?? 'GET',
        headers,
        body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
      });
    } catch {
      throw new ApiException(0, 'Network error — check your connection.');
    }

    if (!res.ok) {
      let detail = '';
      try {
        const data = (await res.json()) as { detail?: unknown };
        if (typeof data.detail === 'string') detail = data.detail;
        else if (data.detail != null) detail = JSON.stringify(data.detail);
      } catch {
        // non-JSON error body — keep detail empty
      }
      throw new ApiException(res.status, detail);
    }

    if (res.status === 204) return undefined as T;
    const text = await res.text();
    if (!text) return undefined as T;
    return JSON.parse(text) as T;
  }

  /**
   * Cached GET with TTL + in-flight dedup. Concurrent identical calls share
   * one promise; failures are never cached.
   */
  private cachedGet<T>(key: string, ttlMs: number, fetch: () => Promise<T>): Promise<T> {
    const now = Date.now();
    const hit = this.cache.get(key);
    if (hit) {
      if (hit.expiresAt > now) return Promise.resolve(hit.data as T);
      this.cache.delete(key);
    }
    const pending = this.inflight.get(key);
    if (pending) return pending as Promise<T>;
    const p = fetch().then(
      (data) => {
        this.inflight.delete(key);
        this.cache.set(key, { data, expiresAt: Date.now() + ttlMs });
        return data;
      },
      (err: unknown) => {
        this.inflight.delete(key);
        throw err;
      },
    );
    this.inflight.set(key, p);
    return p;
  }

  /**
   * Bust cached GETs whose key contains `pattern`. Keys are namespaced
   * (`cards:…`, `collections:…`, `concepts:…`, `me:…`), so e.g.
   * `invalidate('cards:')` clears every card list/detail entry.
   */
  invalidate(pattern: string): void {
    for (const key of this.cache.keys()) {
      if (key.includes(pattern)) this.cache.delete(key);
    }
  }

  // -----------------------------------------------------------------------
  // Cachy ID auth (public endpoints)
  // -----------------------------------------------------------------------

  idRegister(username: string, password: string): Promise<IdRegisterResult> {
    return this.request<IdRegisterResult>('/id/register', {
      method: 'POST',
      body: { username, password },
      public: true,
    });
  }

  idLogin(username: string, password: string): Promise<IdAuthResult> {
    return this.request<IdAuthResult>('/id/login', {
      method: 'POST',
      body: { username, password },
      public: true,
    });
  }

  idReset(username: string, recoveryCode: string, newPassword: string): Promise<IdAuthResult> {
    return this.request<IdAuthResult>('/id/reset', {
      method: 'POST',
      body: { username, recovery_code: recoveryCode, new_password: newPassword },
      public: true,
    });
  }

  idAvailable(username: string): Promise<UsernameAvailableResult> {
    return this.request<UsernameAvailableResult>('/id/available', {
      query: { username },
      public: true,
    });
  }

  idMe(): Promise<IdMeResult> {
    return this.request<IdMeResult>('/id/me');
  }

  // -----------------------------------------------------------------------
  // Cards
  // -----------------------------------------------------------------------

  listCards(
    params?: {
      state?: CardState;
      content_type?: ContentType;
      collection_id?: string;
      limit?: number;
      offset?: number;
    },
    opts?: CacheOptions,
  ): Promise<Card[]> {
    return this.cachedGet<Card[]>(
      `cards:list:${cacheQueryFragment({ ...params })}`,
      opts?.ttlMs ?? DEFAULT_CACHE_TTL_MS,
      () => this.request<Card[]>('/cards', { query: { ...params } }),
    );
  }

  getCard(cardId: string, opts?: CacheOptions): Promise<Card> {
    return this.cachedGet<Card>(
      `cards:get:${cardId}`,
      opts?.ttlMs ?? DEFAULT_CACHE_TTL_MS,
      () => this.request<Card>(`/cards/${encodeURIComponent(cardId)}`),
    );
  }

  async createCard(url: string): Promise<CreateCardResponse> {
    const res = await this.request<CreateCardResponse>('/cards', {
      method: 'POST',
      body: { url },
    });
    this.invalidate('cards:');
    return res;
  }

  async deleteCard(cardId: string): Promise<void> {
    await this.request<void>(`/cards/${encodeURIComponent(cardId)}`, { method: 'DELETE' });
    this.invalidate('cards:');
  }

  async updateActionItems(cardId: string, actionItems: ActionItems): Promise<Card> {
    const card = await this.request<Card>(`/cards/${encodeURIComponent(cardId)}`, {
      method: 'PATCH',
      body: { action_items: actionItems },
    });
    this.invalidate('cards:');
    return card;
  }

  /** Alias kept for callers using the PATCH action-items naming. */
  patchCardActionItems(
    cardId: string,
    actionItems: { followed: boolean; items: ActionItem[] },
  ): Promise<Card> {
    return this.updateActionItems(cardId, actionItems as ActionItems);
  }

  search(q: string, limit = 20): Promise<Card[]> {
    return this.request<Card[]>('/search', { query: { q, limit } });
  }

  // -----------------------------------------------------------------------
  // Sharing
  // -----------------------------------------------------------------------

  createShareLink(cardId: string): Promise<ShareLink> {
    return this.request<ShareLink>(`/cards/${encodeURIComponent(cardId)}/share`, { method: 'POST' });
  }

  getShareLink(cardId: string): Promise<ShareLink | null> {
    return this.request<ShareLink>(`/cards/${encodeURIComponent(cardId)}/share`).catch(
      (e) => {
        if (e instanceof ApiException && e.status === 404) return null;
        throw e;
      },
    );
  }

  revokeShareLink(cardId: string): Promise<void> {
    return this.request<void>(`/cards/${encodeURIComponent(cardId)}/share`, { method: 'DELETE' });
  }

  /** Public: fetch a shared card by token (safe subset, no auth). */
  getSharedCard(token: string): Promise<Card> {
    return this.request<Card>(`/share/${encodeURIComponent(token)}`, { public: true });
  }

  async saveSharedCard(token: string): Promise<SharedCardSaveResult> {
    const res = await this.request<SharedCardSaveResult>(`/share/${encodeURIComponent(token)}/save`, {
      method: 'POST',
    });
    this.invalidate('cards:');
    return res;
  }

  // -----------------------------------------------------------------------
  // Collections
  // -----------------------------------------------------------------------

  listCollections(opts?: CacheOptions): Promise<Collection[]> {
    return this.cachedGet<Collection[]>(
      'collections:list',
      opts?.ttlMs ?? DEFAULT_CACHE_TTL_MS,
      () => this.request<Collection[]>('/collections'),
    );
  }

  async createCollection(name: string): Promise<Collection> {
    const c = await this.request<Collection>('/collections', { method: 'POST', body: { name } });
    this.invalidate('collections:');
    return c;
  }

  async renameCollection(collectionId: string, name: string): Promise<Collection> {
    const c = await this.request<Collection>(`/collections/${encodeURIComponent(collectionId)}`, {
      method: 'PATCH',
      body: { name },
    });
    this.invalidate('collections:');
    return c;
  }

  async moveCardToCollection(cardId: string, collectionId: string | null): Promise<void> {
    await this.request<unknown>(`/collections/cards/${encodeURIComponent(cardId)}/move`, {
      method: 'POST',
      body: { collection_id: collectionId },
    });
    this.invalidate('collections:');
    this.invalidate('cards:');
  }

  // -----------------------------------------------------------------------
  // Catalog / concepts / quota
  // -----------------------------------------------------------------------

  listCatalog(params?: { limit?: number; offset?: number }): Promise<Artifact[]> {
    return this.request<Artifact[]>('/catalog', {
      query: { limit: params?.limit ?? 50, offset: params?.offset ?? 0 },
    });
  }

  deleteCatalogEntry(artifactId: string): Promise<void> {
    return this.request<void>(`/catalog/${encodeURIComponent(artifactId)}`, {
      method: 'DELETE',
    });
  }

  fetchCatalogInfo(artifactId: string): Promise<Artifact> {
    return this.request<Artifact>(`/catalog/${encodeURIComponent(artifactId)}/fetch-info`, {
      method: 'POST',
    });
  }

  listConcepts(
    params?: { limit?: number; offset?: number },
    opts?: CacheOptions,
  ): Promise<Concept[]> {
    const limit = params?.limit ?? 50;
    const offset = params?.offset ?? 0;
    return this.cachedGet<Concept[]>(
      `concepts:list:limit=${limit}&offset=${offset}`,
      opts?.ttlMs ?? DEFAULT_CACHE_TTL_MS,
      () =>
        this.request<Concept[]>('/concepts', {
          query: { limit, offset },
        }),
    );
  }

  getConcept(conceptId: string): Promise<unknown> {
    return this.request<unknown>(`/concepts/${encodeURIComponent(conceptId)}`);
  }

  async defineConcept(conceptId: string): Promise<Concept> {
    const c = await this.request<Concept>(`/concepts/${encodeURIComponent(conceptId)}/define`, {
      method: 'POST',
    });
    this.invalidate('concepts:');
    return c;
  }

  async deleteConcept(conceptId: string): Promise<void> {
    await this.request<void>(`/concepts/${encodeURIComponent(conceptId)}`, {
      method: 'DELETE',
    });
    this.invalidate('concepts:');
  }

  /** Knowledge feed — backend wraps items in `{ items: [...] }`. */
  async feed(limit = 40): Promise<FeedItem[]> {
    const res = await this.request<{ items?: FeedItem[] } | FeedItem[]>('/feed', {
      query: { limit },
    });
    if (Array.isArray(res)) return res;
    return res.items ?? [];
  }

  /** Similarity graph. Backend takes `top_k` (snake_case). */
  graph(params?: { threshold?: number; topK?: number }): Promise<GraphData> {
    return this.request<GraphData>('/graph', {
      query: {
        threshold: params?.threshold ?? 0.55,
        top_k: params?.topK ?? 4,
      },
    });
  }

  /**
   * Discovered connections between cards. Backend (`GET /connections`)
   * wraps pairs in `{ connections: [{card_a, card_b, blurb}] }`.
   */
  async connections(limit = 20, refresh = false): Promise<ConnectionItem[]> {
    const res = await this.request<{ connections?: ConnectionItem[] } | ConnectionItem[]>(
      '/connections',
      { query: { limit, refresh } },
    );
    if (Array.isArray(res)) return res;
    return res.connections ?? [];
  }

  quota(opts?: CacheOptions): Promise<QuotaStatus> {
    return this.cachedGet<QuotaStatus>(
      'me:quota',
      opts?.ttlMs ?? DEFAULT_CACHE_TTL_MS,
      () => this.request<QuotaStatus>('/me/quota'),
    );
  }
}

/** Shared singleton — AuthContext wires the token provider. */
export const api = new ApiClient();

export function apiErrorMessage(err: unknown): string {
  if (err instanceof ApiException) return err.friendlyMessage;
  if (err instanceof Error) return err.message;
  return 'Something went wrong.';
}

/** Alias of {@link apiErrorMessage}. */
export const friendlyError = apiErrorMessage;
