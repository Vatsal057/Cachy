/**
 * The transparent pipeline — port of Flutter's
 * `ui/core/widgets/pipeline_progress.dart` (docs/01, docs/06).
 *
 * A stepped track showing Downloading → Extracting → Structuring → Saving →
 * Analyzing → Cataloging → Concepts as the capture progresses. Done nodes
 * fill with the brand accent, the active node pulses, and connectors fill as
 * work advances — the signature "watch the magic" moment.
 *
 * The web backend reports only the coarse card state over REST (no SSE stage
 * events like the Flutter app's /cards/{id}/stream), so the caller advances
 * `stageIndex` from CardState + elapsed time; the widget itself is a faithful
 * port of the Flutter widget's look and progress math.
 */
import { Check } from 'phosphor-react';
import './capture.css';

export interface PipelineStageInfo {
  label: string;
  description: string;
}

/** Ordered pipeline steps (Flutter `PipelineStage.track`, minus terminal/meta). */
export const PIPELINE_STAGES: PipelineStageInfo[] = [
  { label: 'Downloading', description: 'Fetching the video source' },
  { label: 'Extracting', description: 'Transcript + on-screen text' },
  { label: 'Structuring', description: 'Building your knowledge card' },
  { label: 'Saving', description: 'Saving to your library' },
  { label: 'Analyzing', description: 'Surfacing deeper insight' },
  { label: 'Cataloging', description: 'Extracting referenced items' },
  { label: 'Concepts', description: 'Mapping evergreen concepts' },
];

/**
 * Determinate fraction for a stage index — mirrors
 * `PipelineProgress.calculateProgress`: `(i + 0.5) / track.length`, 0.04
 * before the track starts, 1.0 when done.
 */
export function calculateProgress(stageIndex: number, done = false): number {
  const total = PIPELINE_STAGES.length;
  if (done) return 1;
  if (stageIndex < 0) return 0.04;
  const idx = Math.min(Math.max(stageIndex, 0), total);
  const value = (idx + (idx < total ? 0.5 : 0)) / total;
  return Math.min(Math.max(value, 0), 1);
}

export default function PipelineProgress({
  stageIndex,
  detail = '',
}: {
  /** Index into PIPELINE_STAGES of the active step; -1 = not started yet. */
  stageIndex: number;
  /** Live detail for the active step (falls back to the fixed description). */
  detail?: string;
}) {
  const progress = calculateProgress(stageIndex);
  const pct = Math.round(progress * 100);
  const total = PIPELINE_STAGES.length;

  return (
    <div className="pipeline" aria-label="Capture progress">
      {PIPELINE_STAGES.map((stage, i) => {
        const done = i < stageIndex;
        const active = i === stageIndex;
        const nodeClass = done ? 'done' : active ? 'active' : 'pending';
        const labelClass = done ? 'done' : active ? 'active' : '';
        return (
          <div className="pipe-row" key={stage.label}>
            <div className="pipe-rail" aria-hidden>
              <div className={`pipe-node ${nodeClass}`}>
                {done ? <Check size={17} /> : active ? <span className="pipe-spinner" /> : null}
              </div>
              {i < total - 1 && (
                <div className={`pipe-connector${done ? ' done' : ''}`} />
              )}
            </div>
            <div className="pipe-body">
              <div className={`pipe-label ${labelClass}`}>{stage.label}</div>
              {/* Active step shows the live detail; every other step shows its
                  fixed subtitle so the sequence reads as narrated work. */}
              <div className={`pipe-desc${done || active ? '' : ' dim'}`}>
                {active && detail ? detail : stage.description}
              </div>
            </div>
          </div>
        );
      })}
      <div className="pipe-bar">
        <div className="pipe-bar-fill" style={{ width: `${pct}%` }} />
      </div>
      <div className="pipe-pct" aria-live="polite">
        {pct}% complete
      </div>
    </div>
  );
}
