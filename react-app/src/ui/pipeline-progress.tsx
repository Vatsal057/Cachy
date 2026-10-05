/**
 * PipelineProgress — port of Flutter's ui/core/widgets/pipeline_progress.dart.
 * The transparent pipeline: a stepped track so the user sees the work
 * happening. Done nodes fill with the accent, the active node pulses,
 * connectors fill as work advances — the signature "watch the magic" moment.
 */
import { Check } from 'phosphor-react';
import './widgets.css';

export interface PipelineStageDef {
  label: string;
  description: string;
}

/**
 * Mirrors Flutter's PipelineProgress.calculateProgress.
 * currentIndex: -1 = before the first step (snapshot), stages.length = done.
 */
export function pipelineProgress(
  stages: PipelineStageDef[],
  currentIndex: number,
): number {
  const total = stages.length;
  const idx = currentIndex;
  if (idx < 0) return 0.04;
  const clamped = Math.min(Math.max(idx, 0), total);
  const value = (clamped + (idx < total ? 0.5 : 0)) / total;
  return Math.min(1, Math.max(0, value));
}

export function PipelineProgress({
  stages,
  currentIndex,
  detail = '',
}: {
  stages: PipelineStageDef[];
  /** -1 = pre-start, stages.length = complete. */
  currentIndex: number;
  /** Live detail line for the active step (e.g. the SSE detail). */
  detail?: string;
}) {
  const total = stages.length;
  const progress = pipelineProgress(stages, currentIndex);
  const pct = Math.round(progress * 100);

  return (
    <div className="pipeline-progress">
      {stages.map((stage, i) => {
        const done = i < currentIndex;
        const active = i === currentIndex;
        const lit = done || active;
        return (
          <div key={i} className="pp-row">
            <div className="pp-rail">
              {done ? (
                <span className="pp-node done" aria-hidden>
                  <Check size={17} weight="regular" color="var(--on-accent)" />
                </span>
              ) : active ? (
                <span className="pp-node active" aria-hidden>
                  <span className="spinner pp-node-spinner" />
                </span>
              ) : (
                <span className="pp-node todo" aria-hidden />
              )}
              {i < total - 1 ? (
                <span className={`pp-connector${done ? ' done' : ''}`} aria-hidden />
              ) : null}
            </div>
            <div className="pp-body">
              <div className={`pp-label${active ? ' active' : ''}${done ? ' done' : ''}`}>
                {stage.label}
              </div>
              {(active ? detail || stage.description : stage.description) ? (
                <div className={`pp-desc${lit ? ' lit' : ''}`}>
                  {active ? detail || stage.description : stage.description}
                </div>
              ) : null}
            </div>
          </div>
        );
      })}
      <div
        className="pp-bar"
        role="progressbar"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <div
          className="pp-fill"
          style={{ width: `${pct}%` }}
        />
      </div>
      <div className="pp-pct">{pct}% complete</div>
    </div>
  );
}
