import type {
  ActionItem,
  ActionItems,
  Artifact,
  ArtifactType,
  Block,
  Card,
  CardState,
  CatalogEntry,
  ChatMessage,
  Collection,
  Concept,
  ConceptDetail,
  ConceptEntry,
  ConnectionItem,
  ContentType,
  CreateCardResponse,
  FeedItem,
  GraphData,
  IdAuthResult,
  IdMeResult,
  IdRegisterResult,
  LibraryChatResult,
  PipelineEvent,
  QuotaStatus,
  RabbitHoleStep,
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

export const DEFAULT_BASE_URL = 'https://vatxzz-cachy.hf.space';

/** localStorage key for the developer-screen backend override. */
export const API_BASE_STORAGE_KEY = 'cachy_api_base';

function storedBaseUrl(): string {
  try {
    return localStorage.getItem(API_BASE_STORAGE_KEY) || DEFAULT_BASE_URL;
  } catch {
    return DEFAULT_BASE_URL;
  }
}

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

  constructor(baseUrl: string = storedBaseUrl()) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  /** Called before every authed request to fetch the current token. */
  setTokenProvider(fn: TokenProvider): void {
    this.tokenProvider = fn;
  }

  getBaseUrl(): string {
    return this.baseUrl;
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

  /**
   * Persist user-mutable block state (checked checklist items / steps). Sends
   * the full block array; the server round-trips unknown fields untouched.
   */
  async patchCardBlocks(cardId: string, blocks: Block[]): Promise<Card> {
    const card = await this.request<Card>(`/cards/${encodeURIComponent(cardId)}`, {
      method: 'PATCH',
      body: { blocks },
    });
    this.invalidate('cards:');
    return card;
  }

  /** Restore cards from a device cache after a server wipe (skips known URLs). */
  async importCards(cards: Card[]): Promise<number> {
    if (cards.length === 0) return 0;
    const res = await this.request<{ imported?: number }>('/cards/import', {
      method: 'POST',
      body: { cards },
    });
    this.invalidate('cards:');
    return res?.imported ?? 0;
  }

  // -----------------------------------------------------------------------
  // Chat + rabbit hole (docs/13, docs/14)
  // -----------------------------------------------------------------------

  /**
   * Grounded Q&A over one card. Send the full history each turn; returns the
   * assistant's reply. The conversation is persisted server-side per owner.
   */
  async chat(cardId: string, messages: ChatMessage[]): Promise<string> {
    const res = await this.request<{ reply?: string }>(
      `/cards/${encodeURIComponent(cardId)}/chat`,
      { method: 'POST', body: { messages } },
    );
    this.invalidate('me:');
    return res?.reply ?? '';
  }

  /** Saved chat for a card, oldest → newest. Empty when none. */
  async chatHistory(cardId: string): Promise<ChatMessage[]> {
    const res = await this.request<{ messages?: ChatMessage[] }>(
      `/cards/${encodeURIComponent(cardId)}/chat`,
    );
    return normalizeMessages(res?.messages);
  }

  /**
   * Explore one rabbit-hole thread. Unlike chat this isn't confined to the
   * card: it returns an explanation plus fresh follow-on threads. `trail` is
   * the threads already explored; `root` is the topic that started the dive
   * (persistence key).
   */
  async exploreRabbitHole(
    cardId: string,
    topic: string,
    trail: string[],
    root: string,
  ): Promise<RabbitHoleStep> {
    const res = await this.request<{ explanation?: string; threads?: unknown[] }>(
      `/cards/${encodeURIComponent(cardId)}/rabbithole`,
      { method: 'POST', body: { topic, trail, root } },
    );
    this.invalidate('me:');
    return {
      topic,
      explanation: res?.explanation ?? '',
      threads: (res?.threads ?? []).map(String),
    };
  }

  /** Saved rabbit-hole trail for a card + root topic, oldest → deepest. */
  async rabbitHoleHistory(cardId: string, root: string): Promise<RabbitHoleStep[]> {
    const res = await this.request<{ steps?: Array<Partial<RabbitHoleStep>> }>(
      `/cards/${encodeURIComponent(cardId)}/rabbithole`,
      { query: { root } },
    );
    return (res?.steps ?? []).map((s) => ({
      topic: s.topic ?? '',
      explanation: s.explanation ?? '',
      threads: (s.threads ?? []).map(String),
    }));
  }

  /** Cross-card Q&A. Stateless: replay the full history each turn. */
  async libraryChat(messages: ChatMessage[]): Promise<LibraryChatResult> {
    const res = await this.request<Partial<LibraryChatResult>>('/library/chat', {
      method: 'POST',
      body: { messages },
    });
    this.invalidate('me:');
    return {
      reply: res?.reply ?? '',
      sources: (res?.sources ?? []).map((s) => ({
        card_id: s.card_id ?? '',
        one_liner: s.one_liner ?? '',
      })),
    };
  }

  async libraryChatHistory(): Promise<ChatMessage[]> {
    const res = await this.request<{ messages?: ChatMessage[] }>('/library/chat');
    return normalizeMessages(res?.messages);
  }

  // -----------------------------------------------------------------------
  // Pipeline stream (SSE) — GET /cards/{id}/stream
  // -----------------------------------------------------------------------

  /**
   * Subscribe to the transparent pipeline. The route is Bearer-header only
   * (EventSource can't send headers), so this reads the SSE body with fetch.
   * Calls `onEvent` per stage, resolves when a terminal event arrives or the
   * stream ends. Abort with `signal`. Throws ApiException on HTTP errors.
   */
  async streamCard(
    cardId: string,
    onEvent: (e: PipelineEvent) => void,
    signal?: AbortSignal,
  ): Promise<void> {
    const headers: Record<string, string> = { Accept: 'text/event-stream' };
    const token = this.tokenProvider();
    if (token) headers['Authorization'] = `Bearer ${token}`;
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}/cards/${encodeURIComponent(cardId)}/stream`, {
        headers,
        signal,
      });
    } catch (e) {
      if (signal?.aborted) return;
      throw new ApiException(0, 'Network error — check your connection.');
    }
    if (!res.ok || !res.body) throw new ApiException(res.status, 'stream failed');

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) return;
        buf += decoder.decode(value, { stream: true });
        let idx: number;
        // SSE events end with a blank line.
        while ((idx = buf.search(/\r?\n\r?\n/)) >= 0) {
          const frame = buf.slice(0, idx);
          buf = buf.slice(idx).replace(/^\r?\n\r?\n/, '');
          const data = frame
            .split(/\r?\n/)
            .filter((l) => l.startsWith('data:'))
            .map((l) => l.slice(5).trimStart())
            .join('');
          if (!data) continue; // keep-alive comment frame
          let evt: PipelineEvent;
          try {
            evt = JSON.parse(data) as PipelineEvent;
          } catch {
            continue; // malformed frame — stream stays alive
          }
          onEvent(evt);
          if (evt.state === 'ready' || evt.state === 'failed') return;
        }
      }
    } catch (e) {
      if (signal?.aborted) return;
      throw e;
    } finally {
      reader.cancel().catch(() => undefined);
    }
  }

  // -----------------------------------------------------------------------
  // Account — Instagram auto-save link, guest/legacy migration
  // -----------------------------------------------------------------------

  /** Linked Instagram handle, or null when unlinked. */
  async getInstagramLink(): Promise<string | null> {
    const res = await this.request<{ ig_username?: string | null }>('/me/instagram');
    return res?.ig_username ?? null;
  }

  /** Link a handle; returns the normalized username. */
  async linkInstagram(igUsername: string): Promise<string> {
    const res = await this.request<{ ig_username: string }>('/me/instagram', {
      method: 'POST',
      body: { ig_username: igUsername },
    });
    return res.ig_username;
  }

  async unlinkInstagram(): Promise<void> {
    await this.request<unknown>('/me/instagram', { method: 'DELETE' });
  }

  /** Adopt a legacy name-keyed library; returns rows claimed. 409 = taken. */
  async claimLegacyLibrary(name: string): Promise<number> {
    const res = await this.request<{ claimed?: number }>('/auth/claim', {
      method: 'POST',
      body: { name },
    });
    this.invalidate('cards:');
    return res?.claimed ?? 0;
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

  listCatalog(params?: {
    limit?: number;
    offset?: number;
    type?: ArtifactType;
  }): Promise<Artifact[]> {
    return this.request<Artifact[]>('/catalog', {
      query: {
        type: params?.type,
        limit: params?.limit ?? 50,
        offset: params?.offset ?? 0,
      },
    });
  }

  /** Artifacts a single card references — the reader "References" strip. */
  cardArtifacts(cardId: string, limit = 50): Promise<CatalogEntry[]> {
    return this.request<CatalogEntry[]>('/catalog', {
      query: { card_id: cardId, limit },
    });
  }

  /** Save a referenced artifact into the Catalog tab (long-press to save). */
  saveCatalogEntry(artifactId: string): Promise<CatalogEntry> {
    return this.request<CatalogEntry>(`/catalog/${encodeURIComponent(artifactId)}/save`, {
      method: 'POST',
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

  /** Concepts extracted from one card (reader "Concepts" strip). */
  cardConcepts(cardId: string, limit = 50): Promise<ConceptEntry[]> {
    return this.request<ConceptEntry[]>('/concepts', {
      query: { card_id: cardId, limit },
    });
  }

  /** Typed concept detail: the entry plus related concepts. */
  getConceptDetail(conceptId: string): Promise<ConceptDetail> {
    return this.request<ConceptDetail>(`/concepts/${encodeURIComponent(conceptId)}`);
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

/** Normalise a `messages` array into role/content pairs, dropping empties. */
function normalizeMessages(raw: ChatMessage[] | undefined): ChatMessage[] {
  return (raw ?? [])
    .map((m) => ({
      role: (m?.role === 'assistant' ? 'assistant' : 'user') as ChatMessage['role'],
      content: String(m?.content ?? ''),
    }))
    .filter((m) => m.content.length > 0);
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
