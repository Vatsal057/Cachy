/**
 * StatStrip — port of Flutter's ui/core/widgets/stat_strip.dart.
 * A compact dashboard strip: a row of boxed value/label cells. Editorial,
 * flat — bordered cells on the surface, no glow.
 */
import './widgets.css';

export interface Stat {
  value: string;
  label: string;
  /** Tint the value in the brand accent (the headline stat). */
  emphasize?: boolean;
}

export function StatStrip({ stats }: { stats: Stat[] }) {
  if (stats.length === 0) return null;
  return (
    <div className="stat-strip" role="group">
      {stats.map((s, i) => (
        <div key={i} className="stat-cell">
          <div className={`stat-value${s.emphasize ? ' accent' : ''}`}>
            {s.value}
          </div>
          <div className="stat-label">{s.label.toUpperCase()}</div>
        </div>
      ))}
    </div>
  );
}
