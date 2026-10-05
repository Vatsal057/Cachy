/**
 * Shared empty / error / loading feedback states — port of Flutter's
 * ui/core/widgets/empty_state.dart and error_state.dart.
 *
 * Kept backwards-compatible: LoadingState, EmptyState, ErrorState retain
 * their previous prop shapes; EmptyState adds an optional `art` slot.
 */
import type { ReactNode } from 'react';
import { isValidElement, useCallback, useEffect, useRef, useState } from 'react';
import {
  ArrowClockwise,
  CheckCircle,
  Info,
  Warning,
  WifiSlash,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import './feedback.css';
import './widgets.css';

/** Skeleton shimmer block for list-like loading states. */
export function LoadingState({
  label,
  lines = 3,
}: {
  label?: string;
  lines?: number;
}) {
  return (
    <div className="feedback" role="status" aria-live="polite">
      {label ? <p className="feedback-title">{label}</p> : null}
      <div className="skeleton-list">
        {Array.from({ length: lines }).map((_, i) => (
          <div
            key={i}
            className="skeleton-line shimmer"
            style={{ animationDelay: `${i * 90}ms` }}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * Normalize the `icon` prop: a Phosphor component passed directly
 * (`icon={MagnifyingGlass}`) is instantiated at the default art size;
 * an already-built node passes through untouched.
 */
function resolveIcon(icon: ReactNode | Icon | undefined): ReactNode {
  if (!icon || isValidElement(icon)) return icon;
  const C = icon as Icon;
  return <C size={40} weight="regular" color="var(--muted)" aria-hidden />;
}

/** Hand-drawn placeholder for states with no content. */
export function EmptyState({
  title,
  hint,
  message,
  actionLabel,
  onAction,
  icon,
  art,
}: {
  title: string;
  hint?: string;
  /** Deprecated alias for `hint` — kept so existing callers keep working. */
  message?: string;
  actionLabel?: string;
  onAction?: () => void;
  /**
   * Optional Phosphor icon shown when no `art` is supplied. Accepts the
   * component itself (`icon={MagnifyingGlass}`) or a ready-made node.
   */
  icon?: ReactNode | Icon;
  /** Optional spot-art illustration rendered above the title. */
  art?: ReactNode;
}) {
  const hintText = hint ?? message;
  return (
    <div className="feedback">
      <div className="feedback-art">
        {art ?? (
          resolveIcon(icon) ?? (
            <Info
              size={40}
              weight="regular"
              color="var(--muted)"
              aria-hidden
            />
          )
        )}
      </div>
      <p className="feedback-title">{title}</p>
      {hintText ? <p className="feedback-hint">{hintText}</p> : null}
      {actionLabel && onAction ? (
        <button type="button" className="feedback-btn" onClick={onAction}>
          {actionLabel}
        </button>
      ) : null}
    </div>
  );
}

/**
 * Error notice with a retry action and, on failure, the raw message. When
 * `onRetry` is present the state auto-retries once when it first appears
 * (Flutter's ErrorState is built around this pattern).
 */
export function ErrorState({
  title,
  message,
  onRetry,
  retryLabel = 'Try again',
  icon,
}: {
  /** Heading — defaults to "Something went wrong". */
  title?: string;
  message: string;
  onRetry?: () => void;
  retryLabel?: string;
  /** Override the default offline glyph. */
  icon?: ReactNode;
}) {
  const [failedOnce, setFailedOnce] = useState(false);

  useEffect(() => {
    if (onRetry && !failedOnce) {
      setFailedOnce(true);
      const t = window.setTimeout(onRetry, 400);
      return () => window.clearTimeout(t);
    }
  }, [onRetry, failedOnce]);

  return (
    <div className="feedback" role="alert">
      <div className="feedback-art">
        {icon ?? (
          <WifiSlash size={40} weight="regular" color="var(--muted)" aria-hidden />
        )}
      </div>
      <p className="feedback-title">{title ?? 'Something went wrong'}</p>
      <p className="feedback-hint">{message}</p>
      {onRetry ? (
        <button type="button" className="feedback-btn" onClick={onRetry}>
          <ArrowClockwise size={16} weight="regular" aria-hidden />
          {retryLabel}
        </button>
      ) : null}
    </div>
  );
}

/** Compact inline alert strip (info / warning / error). */
export function AlertStrip({
  kind,
  message,
}: {
  kind: 'info' | 'warning' | 'error';
  message: string;
}) {
  const Glyph =
    kind === 'warning' ? Warning : kind === 'error' ? Warning : Info;
  return (
    <div className={`alert-strip ${kind}`} role="status">
      <Glyph size={16} weight="regular" aria-hidden />
      <span>{message}</span>
    </div>
  );
}

/** Small centered confirmation panel (e.g. after an action succeeds). */
export function SuccessNote({ message }: { message: string }) {
  return (
    <div className="feedback" role="status">
      <CheckCircle size={40} weight="regular" color="var(--accent)" aria-hidden />
      <p className="feedback-title">{message}</p>
    </div>
  );
}

/**
 * Simple dialog used by folder rename/create flows.
 * Backdrop click and Escape dismiss; `actions` renders the footer buttons.
 */
export function Modal({
  title,
  onClose,
  actions,
  children,
}: {
  title: string;
  onClose: () => void;
  actions?: ReactNode;
  children: ReactNode;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="modal-head">
          <h2 className="modal-title">{title}</h2>
        </div>
        <div className="modal-body">{children}</div>
        {actions ? <div className="modal-actions">{actions}</div> : null}
      </div>
    </div>
  );
}

/**
 * Minimal toast hook. `showToast(message)` displays a transient toast;
 * render `toastNode` where the toast should appear.
 */
export function useToast() {
  const [toast, setToast] = useState<string | null>(null);
  const timer = useRef<number | null>(null);

  const showToast = useCallback((message: string) => {
    setToast(message);
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 2200);
  }, []);

  useEffect(() => {
    return () => {
      if (timer.current) window.clearTimeout(timer.current);
    };
  }, []);

  const toastNode = toast ? (
    <div className="toast" role="status" aria-live="polite">
      {toast}
    </div>
  ) : null;

  return { showToast, toastNode };
}
