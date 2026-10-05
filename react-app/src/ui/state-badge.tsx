/**
 * StateBadge — port of Flutter's ui/core/widgets/state_badge.dart.
 * Compact state badge for the library grid: queued / processing / failed.
 * Ready cards show no badge — the face speaks for itself.
 */
import { Clock, Warning } from 'phosphor-react';
import { CardState } from '../api/types';
import { failureLabel } from './content-accent';
import './widgets.css';

export function StateBadge({
  state,
  reason,
}: {
  state: CardState;
  reason?: string | null;
}) {
  if (state === CardState.READY) return null;

  if (state === CardState.PROCESSING) {
    return (
      <span className="state-badge-ui" role="status">
        <span className="sb-spinner" aria-hidden />
        <span className="sb-label">Working</span>
      </span>
    );
  }

  if (state === CardState.FAILED) {
    return (
      <span className="state-badge-ui" role="status">
        <Warning size={13} color="#FF8A7A" weight="regular" aria-hidden />
        <span className="sb-label" style={{ color: '#FF8A7A' }}>
          {failureLabel(reason)}
        </span>
      </span>
    );
  }

  // Queued.
  return (
    <span className="state-badge-ui" role="status">
      <Clock size={13} color="rgba(255,255,255,0.7)" weight="regular" aria-hidden />
      <span className="sb-label" style={{ color: 'rgba(255,255,255,0.7)' }}>
        Queued
      </span>
    </span>
  );
}
