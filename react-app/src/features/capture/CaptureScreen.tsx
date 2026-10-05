/**
 * Capture — the in-app twin of the OS share target.
 * Entry form mirrors capture_sheet.dart (platform chips, clipboard chip,
 * link field, Capture button); the visible pipeline mirrors share_screen.dart
 * (sending state, determinate progress ring, live PipelineProgress track,
 * designed failure view, spring-pop success) before the auto-advance into
 * the reader.
 */
import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowClockwise,
  ArrowRight,
  Article,
  Check,
  ClipboardText,
  Globe,
  InstagramLogo,
  Link as LinkIcon,
  LinkedinLogo,
  MediumLogo,
  Sparkle,
  TiktokLogo,
  TwitterLogo,
  Warning,
  YoutubeLogo,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import { CardState } from '../../api/types';
import PipelineProgress, {
  calculateProgress,
  PIPELINE_STAGES,
} from './PipelineProgress';
import './capture.css';

/* ------------------------------------------------------------------ */
/* Source platforms — entry chips (capture_sheet.dart) + pipeline     */
/* badge/detection (source_platform.dart, share_screen.dart)          */
/* ------------------------------------------------------------------ */

interface Platform {
  label: string;
  color: string;
  Icon: Icon;
  /** Uppercase status line shown while fetching, e.g. "INGESTING VIDEO STREAM". */
  ingesting: string;
}

/** Supported-platform affordance chips (capture_sheet.dart _PlatformChip). */
const ENTRY_PLATFORMS: { label: string; color: string }[] = [
  { label: 'Instagram', color: '#E1306C' },
  { label: 'YouTube', color: '#E0301E' },
  { label: 'X / Twitter', color: '#000000' },
  { label: 'Wikipedia', color: '#3A85C8' },
  { label: 'Substack', color: '#FF6719' },
  { label: 'Medium', color: '#1A8917' },
  { label: 'LinkedIn', color: '#0A66C2' },
];

const DETECTABLE: Platform[] = [
  {
    label: 'Instagram',
    color: '#E1306C',
    Icon: InstagramLogo,
    ingesting: 'INGESTING VIDEO STREAM',
  },
  {
    label: 'YouTube',
    color: '#E0301E',
    Icon: YoutubeLogo,
    ingesting: 'INGESTING VIDEO STREAM',
  },
  {
    label: 'TikTok',
    color: '#1A1A1A',
    Icon: TiktokLogo,
    ingesting: 'INGESTING VIDEO STREAM',
  },
  {
    label: 'X / Twitter',
    color: '#1A1A1A',
    Icon: TwitterLogo,
    ingesting: 'INGESTING POST',
  },
  {
    label: 'Wikipedia',
    color: '#3A85C8',
    Icon: Globe,
    ingesting: 'INGESTING ARTICLE',
  },
  {
    label: 'Substack',
    color: '#FF6719',
    Icon: Article,
    ingesting: 'INGESTING ARTICLE',
  },
  {
    label: 'Medium',
    color: '#1A8917',
    Icon: MediumLogo,
    ingesting: 'INGESTING ARTICLE',
  },
  {
    label: 'LinkedIn',
    color: '#0A66C2',
    Icon: LinkedinLogo,
    ingesting: 'INGESTING POST',
  },
];

const FALLBACK_PLATFORM: Platform = {
  label: 'Link',
  color: '#8A8378',
  Icon: LinkIcon,
  ingesting: 'FETCHING CONTENT',
};

/**
 * Lightweight source detection from a shared URL's host — turns a bare link
 * into a recognizable platform + content-kind label (source_platform.dart).
 */
function detectPlatform(url: string): Platform {
  let host = '';
  try {
    host = new URL(url.trim()).hostname.toLowerCase();
  } catch {
    host = url.toLowerCase();
  }
  const has = (needle: string) => host.includes(needle);
  if (has('instagram.com')) return DETECTABLE[0];
  if (has('youtube.com') || has('youtu.be')) return DETECTABLE[1];
  if (has('tiktok.com')) return DETECTABLE[2];
  if (has('twitter.com') || has('x.com')) return DETECTABLE[3];
  if (has('wikipedia.org')) return DETECTABLE[4];
  if (has('substack.com')) return DETECTABLE[5];
  if (has('medium.com')) return DETECTABLE[6];
  if (has('linkedin.com')) return DETECTABLE[7];
  return FALLBACK_PLATFORM;
}

/* ------------------------------------------------------------------ */
/* Pipeline phases                                                     */
/* ------------------------------------------------------------------ */

type Phase = 'idle' | 'saving' | 'queued' | 'processing' | 'ready' | 'error';

/**
 * Ms each pipeline step shows before the track advances. Time-estimated:
 * the REST backend only reports the coarse card state (queued/processing),
 * not per-stage SSE events like the Flutter app's /cards/{id}/stream.
 */
const STAGE_DWELL_MS = 8000;

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));
const URL_PATTERN = /https?:\/\/[^\s]+/;

/** Named failure copy, mirroring share_screen.dart _resolveErrorDetails. */
function resolveErrorDetails(reason: string): { title: string; description: string } {
  const lower = reason.toLowerCase();
  if (lower.includes('still working')) {
    return {
      title: 'Request timed out',
      description: 'The server took too long to respond. Tap try again to retry.',
    };
  }
  if (lower.includes('on our side') || lower.includes('server') || lower.includes('50')) {
    return {
      title: 'Server temporarily unavailable',
      description: "Cachy couldn't be reached or is restarting. Please try again in a moment.",
    };
  }
  if (lower.includes('session') || lower.includes('sign in')) {
    return {
      title: 'Session expired',
      description: 'Please sign in again to continue capturing reels.',
    };
  }
  if (lower.includes('limit')) {
    return {
      title: 'Daily limit reached',
      description: "You've reached your daily capture limit. It resets at midnight UTC.",
    };
  }
  if (lower.includes('time') && lower.includes('out')) {
    return {
      title: 'Request timed out',
      description: 'The server took too long to respond. Tap try again to retry.',
    };
  }
  return {
    title: 'Unsupported content',
    description:
      "The video may be private, unavailable in your region, or the link format isn't supported.",
  };
}

/** 'Capturing' header + source URL chip (share_screen.dart AppBar + _UrlChip). */
function CaptureFlowHead({ url, platform }: { url: string; platform: Platform }) {
  return (
    <>
      <h1 className="headline-sm capture-flow-title">Capturing</h1>
      <div className="url-chip">
        <platform.Icon size={18} style={{ color: platform.color }} aria-hidden />
        <span className="url-chip-url">{url}</span>
        <span className="url-chip-label">{platform.label}</span>
      </div>
    </>
  );
}

export default function CaptureScreen() {
  const navigate = useNavigate();
  const [url, setUrl] = useState('');
  const [clipboardUrl, setClipboardUrl] = useState<string | null>(null);
  const [phase, setPhase] = useState<Phase>('idle');
  const [error, setError] = useState('');
  const [activeUrl, setActiveUrl] = useState('');
  const [cardId, setCardId] = useState<string | null>(null);
  const [stageIndex, setStageIndex] = useState(-1);
  const cancelled = useRef(false);
  const startedAt = useRef(0);

  useEffect(() => {
    cancelled.current = false;
    return () => {
      cancelled.current = true;
    };
  }, []);

  // Sniff the clipboard for a URL on entry (capture_sheet.dart _sniffClipboard).
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const text = await navigator.clipboard.readText();
        const match = URL_PATTERN.exec(text ?? '');
        if (alive && match) setClipboardUrl(match[0]);
      } catch {
        // No clipboard access — paste still works.
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  // Auto-advance into the reader shortly after the card is ready, so the
  // success beat still lands (share_screen.dart auto-advances on ready).
  useEffect(() => {
    if (phase !== 'ready' || !cardId) return;
    const t = window.setTimeout(() => navigate(`/reader/${cardId}`), 1400);
    return () => window.clearTimeout(t);
  }, [phase, cardId, navigate]);

  const busy = phase === 'saving' || phase === 'queued' || phase === 'processing';
  const platform = detectPlatform(activeUrl || url);
  const progress = calculateProgress(stageIndex);

  async function save(raw: string) {
    const trimmed = raw.trim();
    if (!trimmed || busy) return;
    cancelled.current = false;
    startedAt.current = Date.now();
    setError('');
    setActiveUrl(trimmed);
    setCardId(null);
    setStageIndex(-1);
    setPhase('saving');
    try {
      const res = await api.createCard(trimmed);
      if (cancelled.current) return;
      setCardId(res.card_id);
      if (res.state === CardState.READY) {
        // Deduped — the card already exists; jump straight to it.
        setPhase('ready');
        return;
      }
      setPhase(res.state === CardState.PROCESSING ? 'processing' : 'queued');
      setStageIndex(0);
      // Poll until the card is ready (up to ~3 minutes). ttlMs 0: the client
      // caches GETs for 60s — never serve a stale state here.
      for (let i = 0; i < 90; i++) {
        await sleep(2000);
        if (cancelled.current) return;
        const card = await api.getCard(res.card_id, { ttlMs: 0 });
        if (card.state === CardState.READY) {
          setPhase('ready');
          return;
        }
        if (card.state === CardState.FAILED) {
          setPhase('error');
          setError(card.failure_reason || "Couldn't process that link.");
          return;
        }
        setPhase(card.state === CardState.PROCESSING ? 'processing' : 'queued');
        setStageIndex(
          Math.min(
            PIPELINE_STAGES.length - 1,
            Math.floor((Date.now() - startedAt.current) / STAGE_DWELL_MS),
          ),
        );
      }
      setPhase('error');
      setError('Still working on it — check your library in a bit.');
    } catch (e) {
      if (!cancelled.current) {
        setPhase('error');
        setError(friendlyError(e));
      }
    }
  }

  function cancel() {
    cancelled.current = true;
    setPhase('idle');
    setError('');
    setActiveUrl('');
    setCardId(null);
    setStageIndex(-1);
  }

  function reset() {
    setPhase('idle');
    setError('');
    setActiveUrl('');
    setCardId(null);
    setStageIndex(-1);
  }

  const failed = resolveErrorDetails(error);
  const processing = phase === 'queued' || phase === 'processing';

  return (
    <div className={`page${phase === 'saving' || processing ? ' capture-processing' : ''}`}>
      <div className="capture-wrap">
        {phase === 'idle' && (
          <>
            <h1 className="headline-sm">Capture anything</h1>
            <p className="muted capture-desc">
              Videos, articles, newsletters — paste any link and Cachy builds a knowledge card.
            </p>

            <div className="platform-chips" aria-label="Supported platforms">
              {ENTRY_PLATFORMS.map((p) => (
                <span key={p.label} className="platform-chip">
                  <span className="platform-dot" style={{ background: p.color }} aria-hidden />
                  {p.label}
                </span>
              ))}
            </div>

            {clipboardUrl && (
              <button
                type="button"
                className="clipboard-chip"
                onClick={() => void save(clipboardUrl)}
              >
                <ClipboardText size={20} aria-hidden />
                <span className="clipboard-body">
                  <span className="clipboard-label">CAPTURE FROM CLIPBOARD</span>
                  <span className="clipboard-url">{clipboardUrl}</span>
                </span>
                <ArrowRight size={18} aria-hidden />
              </button>
            )}

            <div className="capture-field">
              <LinkIcon size={20} className="capture-field-icon" aria-hidden />
              <input
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') void save(url);
                }}
                placeholder="Paste any link…"
                inputMode="url"
                autoCapitalize="off"
                autoCorrect="off"
                autoFocus={!clipboardUrl}
                aria-label="Link to capture"
              />
            </div>

            <button
              type="button"
              className="btn btn-block"
              onClick={() => void save(url)}
              disabled={busy}
            >
              <Sparkle size={20} aria-hidden />
              Capture
            </button>
          </>
        )}

        {phase === 'saving' && (
          <div className="capture-progress">
            <div className="send-badge" aria-hidden>
              <div
                className="progress-halo"
                style={{ '--platform-color': platform.color } as CSSProperties}
              >
                <div className="progress-badge" style={{ background: platform.color }}>
                  <platform.Icon size={24} color="#fff" aria-hidden />
                </div>
              </div>
            </div>
            <h2 className="capture-headline-sm">Sending to Cachy…</h2>
            <p className="capture-ingest">
              {platform.label.toUpperCase()} · {platform.ingesting}
            </p>
          </div>
        )}

        {processing && (
          <div className="capture-progress">
            <div
              className="progress-ring"
              role="progressbar"
              aria-label="Building your card"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round(progress * 100)}
            >
              <svg viewBox="0 0 140 140" aria-hidden>
                <circle cx="70" cy="70" r="62" className="ring-track" />
                <circle
                  cx="70"
                  cy="70"
                  r="62"
                  className="ring-fill"
                  style={{ '--ring-progress': progress } as CSSProperties}
                />
              </svg>
              <div className="progress-center">
                <div
                  className="progress-halo"
                  style={{ '--platform-color': platform.color } as CSSProperties}
                >
                  <div className="progress-badge" style={{ background: platform.color }}>
                    <platform.Icon size={24} color="#fff" aria-hidden />
                  </div>
                </div>
              </div>
            </div>
            <h2 className="capture-headline">Building your card</h2>
            <p className="muted capture-sub">
              From {platform.label} · usually under 30 seconds
            </p>
            <PipelineProgress stageIndex={stageIndex} />
            <button type="button" className="capture-cancel" onClick={cancel}>
              Cancel
            </button>
          </div>
        )}

        {phase === 'ready' && (
          <>
            <CaptureFlowHead url={activeUrl} platform={platform} />
            <div className="ready-wrap">
              <div className="ready-badge" aria-hidden>
                <Check size={46} />
              </div>
              <h2 className="ready-title">Card ready</h2>
              {cardId && (
                <button
                  type="button"
                  className="ready-cta"
                  onClick={() => navigate(`/reader/${cardId}`)}
                >
                  Open card
                </button>
              )}
            </div>
          </>
        )}

        {phase === 'error' && (
          <>
            <CaptureFlowHead url={activeUrl} platform={platform} />
            <div className="capture-error">
              <div className="warning-glyph" aria-hidden>
                <div className="warning-badge">
                  <Warning size={30} />
                </div>
              </div>
              <h2 className="capture-headline">Something went wrong</h2>
              <p className="muted capture-sub">We couldn&apos;t process this reel</p>
              <div className="capture-error-card">
                <div className="capture-error-head">
                  <Warning size={18} aria-hidden />
                  <span>{failed.title}</span>
                </div>
                <p className="capture-error-desc">{failed.description}</p>
                {error && <div className="capture-error-reason">{error}</div>}
              </div>
              <button type="button" className="btn btn-block" onClick={() => void save(activeUrl || url)}>
                <ArrowClockwise size={20} aria-hidden />
                Try again
              </button>
              <button type="button" className="capture-cancel-outline" onClick={reset}>
                Cancel
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
