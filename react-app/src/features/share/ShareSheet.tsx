import { useEffect, useRef, useState } from 'react';
import { Copy, ShareNetwork, Trash } from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import './ShareSheet.css';

interface ShareSheetProps {
  cardId: string;
  onClose?: () => void;
}

type Status = 'loading' | 'ready' | 'error';

/**
 * The card's public link: copy it, send it through the OS share sheet, or
 * revoke it (revoked links stop opening immediately).
 * Port of Flutter's _ShareOptionsSheet — the link is get-or-created before
 * the sheet shows, and revoking needs no confirmation.
 */
export default function ShareSheet({ cardId, onClose }: ShareSheetProps) {
  const [url, setUrl] = useState<string | null>(null);
  const [status, setStatus] = useState<Status>('loading');
  const [error, setError] = useState('');
  const [revoking, setRevoking] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const existing = await api.getShareLink(cardId);
        const link = existing ?? (await api.createShareLink(cardId));
        if (!cancelled) {
          setUrl(link.url);
          setStatus('ready');
        }
      } catch (e) {
        if (!cancelled) {
          setError(friendlyError(e));
          setStatus('error');
        }
      }
    })();
    return () => {
      cancelled = true;
      if (toastTimer.current != null) window.clearTimeout(toastTimer.current);
    };
  }, [cardId]);

  const showToast = (msg: string) => {
    setToast(msg);
    if (toastTimer.current != null) window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 2200);
  };

  const copyText = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }
  };

  const copyLink = async () => {
    if (!url) return;
    await copyText(url);
    showToast('Link copied');
  };

  const shareOs = async () => {
    if (!url) return;
    const nav = navigator as Navigator & {
      share?: (data: { title?: string; text?: string; url?: string }) => Promise<void>;
    };
    if (typeof nav.share === 'function') {
      try {
        await nav.share({ title: 'Shared from Cachy', url });
        return;
      } catch {
        // User dismissed the OS sheet — nothing to do.
        return;
      }
    }
    await copyText(url);
    showToast('Link copied');
  };

  const revokeLink = async () => {
    if (revoking) return;
    setRevoking(true);
    setError('');
    try {
      await api.revokeShareLink(cardId);
      showToast('Share link revoked');
      onClose?.();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setRevoking(false);
    }
  };

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="Share this card">
        <div className="sheet-handle" />
        <h2 className="sheet-title" style={{ marginTop: 12 }}>
          Share this card
        </h2>
        <p className="muted sheet-sub">
          Anyone with the link can view it — no Cachy account needed.
        </p>

        {status === 'loading' && (
          <div className="share-loading" role="status">
            <div className="spinner" aria-hidden />
            <span>Creating link…</span>
          </div>
        )}

        {status === 'error' && (
          <div className="error-card" role="alert">
            {error || "Couldn't create the share link. Try again."}
          </div>
        )}

        {status === 'ready' && url && (
          <>
            <div className="share-url-row">
              <span className="share-url-text">{url}</span>
              <button
                className="share-copy-btn"
                onClick={copyLink}
                aria-label="Copy link"
                title="Copy link"
              >
                <Copy size={20} />
              </button>
            </div>
            <button className="share-primary" onClick={shareOs}>
              <ShareNetwork size={20} />
              Share…
            </button>
            <button
              className="share-revoke"
              onClick={revokeLink}
              disabled={revoking}
            >
              <Trash size={18} />
              {revoking ? 'Revoking…' : 'Revoke link'}
            </button>
          </>
        )}

        {error && status === 'ready' && (
          <div className="error-card" role="alert">
            {error}
          </div>
        )}

        {onClose && (
          <button className="btn btn-ghost sheet-close" onClick={onClose}>
            Close
          </button>
        )}
      </div>
      {toast && (
        <div className="share-toast" role="status">
          {toast}
        </div>
      )}
    </div>
  );
}
