/**
 * AdaptiveModal — port of Flutter's ui/core/widgets/adaptive_modal.dart.
 * A modal that's a bottom sheet on mobile/narrow widths and a centered dialog
 * on desktop widths (>= 600px). Children-as-function receive `dialog: true`
 * when rendered as a desktop dialog, so content can drop its drag-handle pill
 * and round all four corners.
 */
import { useEffect } from 'react';
import type { ReactNode } from 'react';
import { useMedia } from './use-media';
import './widgets.css';

export function AdaptiveModal({
  children,
  onClose,
  dialogMaxWidth = 480,
  labelledBy,
}: {
  children: ReactNode | ((dialog: boolean) => ReactNode);
  onClose: () => void;
  dialogMaxWidth?: number;
  labelledBy?: string;
}) {
  const dialog = useMedia('(min-width: 600px)');

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const body = typeof children === 'function' ? children(dialog) : children;

  if (!dialog) {
    return (
      <div
        className="adaptive-backdrop"
        onClick={onClose}
        role="presentation"
      >
        <div
          className="adaptive-sheet"
          role="dialog"
          aria-modal="true"
          aria-label={labelledBy}
          onClick={(e) => e.stopPropagation()}
        >
          <div className="sheet-handle" aria-hidden />
          {body}
        </div>
      </div>
    );
  }

  return (
    <div className="adaptive-backdrop" onClick={onClose} role="presentation">
      <div
        className="adaptive-dialog"
        role="dialog"
        aria-modal="true"
        aria-label={labelledBy}
        style={{ maxWidth: dialogMaxWidth }}
        onClick={(e) => e.stopPropagation()}
      >
        {body}
      </div>
    </div>
  );
}
