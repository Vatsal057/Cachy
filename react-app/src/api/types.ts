/** TypeScript mirrors of the backend block schema (docs/04, schema 1.6).
 *  Source of truth is backend/app/models/card.py — keep in sync manually.
 */

export enum CardState {
  QUEUED = 'queued',
  PROCESSING = 'processing',
  READY = 'ready',
  FAILED = 'failed',
}

export enum ContentType {
  RECIPE = 'recipe',
  WORKOUT = 'workout',
  TUTORIAL = 'tutorial',
  TIP = 'tip',
  PRODUCT_LIST = 'product_list',
  TRAVEL = 'travel',
  NEWS_EXPLAINER = 'news_explainer',
  OTHER = 'other',
}

// ---------------------------------------------------------------------------
// Blocks — discriminated union on `type`.
// ---------------------------------------------------------------------------

interface BlockBase {
  id: string;
  type: string;
}

export interface HeadingBlock extends BlockBase {
  type: 'heading';
  text: string;
  /** Level can arrive as null from older rows — BlockRenderer coerces to 2. */
  level?: number | null;
}

export interface ParagraphBlock extends BlockBase {
  type: 'paragraph';
  text: string;
}

export interface BulletListBlock extends BlockBase {
  type: 'bullet_list';
  items: string[];
}

export interface StepItem {
  text: string;
  checkable?: boolean;
  checked?: boolean;
}

export interface StepListBlock extends BlockBase {
  type: 'step_list';
  steps: StepItem[];
}

export interface ChecklistItem {
  text: string;
  checked: boolean;
}

export interface ChecklistBlock extends BlockBase {
  type: 'checklist';
  items: ChecklistItem[];
}

export interface KeyValuePair {
  key: string;
  value: string;
}

export interface KeyValueBlock extends BlockBase {
  type: 'key_value';
  pairs: KeyValuePair[];
}

export type CalloutVariant = 'info' | 'warning' | 'caveat' | 'source';

export interface CalloutBlock extends BlockBase {
  type: 'callout';
  variant: CalloutVariant;
  text: string;
  confidence?: 'high' | 'medium' | 'low' | 'unverified';
  source_url?: string | null;
}

export interface TableBlock extends BlockBase {
  type: 'table';
  headers: string[];
  rows: string[][];
}

export interface Place {
  name: string;
  lat?: number | null;
  lng?: number | null;
  note?: string;
}

export interface MapBlock extends BlockBase {
  type: 'map';
  places: Place[];
}

export interface LinkBlock extends BlockBase {
  type: 'link';
  url: string;
  label?: string | null;
}

/**
 * Forward-compat: any unknown block type degrades gracefully.
 * BlockRenderer renders text/items when present, else skips.
 */
export interface UnknownBlock extends BlockBase {
  [key: string]: unknown;
}

export type Block =
  | HeadingBlock
  | ParagraphBlock
  | BulletListBlock
  | StepListBlock
  | ChecklistBlock
  | KeyValueBlock
  | CalloutBlock
  | TableBlock
  | MapBlock
  | LinkBlock
  | UnknownBlock;

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

export interface CardSource {
  url: string;
  platform?: string | null;
  creator?: string | null;
  caption?: string;
  duration_seconds?: number | null;
}

export interface CardBase {
  one_liner: string;
  tldr?: string;
  content_type: ContentType;
  type_confidence?: number;
  tags?: string[];
}

export interface ActionItem {
  id: string;
  text: string;
  done: boolean;
}

export interface ActionItems {
  followed: boolean;
  items: ActionItem[];
}

export interface CardMedia {
  thumbnail?: string | null;
  keyframes?: string[];
}

export interface CardMeta {
  created_at?: string;
}

export interface Card {
  schema_version: string;
  card_id: string;
  state: CardState;
  failure_reason?: string | null;
  source: CardSource;
  base: CardBase;
  action_items?: ActionItems;
  blocks: Block[];
  media?: CardMedia;
  meta?: CardMeta;
  collection_id?: string | null;
}

// ---------------------------------------------------------------------------
// Collections / catalog / concepts
// ---------------------------------------------------------------------------

export interface Collection {
  id: string;
  name: string;
  system_type: string | null;
  is_custom: boolean;
  card_count: number;
  created_at: string;
}

export interface Artifact {
  artifact_id: string;
  title?: string;
  kind?: string;
  [key: string]: unknown;
}

export interface Concept {
  concept_id: string;
  name?: string;
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Quota
// ---------------------------------------------------------------------------

export interface QuotaMeter {
  used: number;
  limit: number;
}

export interface QuotaStatus {
  resets_at?: string;
  cards?: QuotaMeter;
  chat?: QuotaMeter;
}

// ---------------------------------------------------------------------------
// Feed
// ---------------------------------------------------------------------------

export interface FeedCardRef {
  card_id: string;
  title: string;
  content_type: string;
  thumbnail?: string | null;
}

export interface FeedItem {
  id: string;
  kind: string; // insight | highlight | quiz | thread | connection
  card: FeedCardRef;
  text?: string;
  question?: string;
  options?: string[];
  answer_index?: number;
  explanation?: string;
  card_b?: FeedCardRef | null;
}

// ---------------------------------------------------------------------------
// Connections (serendipity engine — backend/app/api/connections.py)
// ---------------------------------------------------------------------------

export interface ConnectionItem {
  card_a: FeedCardRef;
  card_b: FeedCardRef;
  blurb: string;
}

// ---------------------------------------------------------------------------
// Graph
// ---------------------------------------------------------------------------

export interface GraphNode {
  id: string;
  label?: string;
  node_type?: string;
  cluster_id?: string | number | null;
  [key: string]: unknown;
}

export interface GraphEdge {
  source: string;
  target: string;
  kind?: string;
  shared_topics?: string[];
  [key: string]: unknown;
}

export interface GraphData {
  nodes: GraphNode[];
  edges: GraphEdge[];
  clusters?: unknown[];
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export interface IdAuthResult {
  uid: string;
  username: string;
  token: string;
}

export interface IdRegisterResult extends IdAuthResult {
  recovery_code: string;
}

export interface IdMeResult {
  uid: string;
  username: string | null;
}

export interface UsernameAvailableResult {
  available: boolean;
  reason?: string;
}

// ---------------------------------------------------------------------------
// Share
// ---------------------------------------------------------------------------

export interface ShareLink {
  url: string;
  token: string;
}

export interface SharedCardSaveResult {
  card_id: string;
  already_saved: boolean;
  is_owner?: boolean;
}

// ---------------------------------------------------------------------------
// Misc responses
// ---------------------------------------------------------------------------

export interface CreateCardResponse {
  card_id: string;
  state: CardState;
  cached?: boolean;
  quota_degraded?: boolean;
}
