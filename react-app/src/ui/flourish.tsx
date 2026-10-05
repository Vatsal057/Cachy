/**
 * Flourish — port of Flutter's ui/core/widgets/flourish.dart.
 * A calm editorial flourish: a small accent lozenge with two symmetric
 * tapering tendrils. Cachy's quiet answer to a magazine fleuron: "an
 * underline, not a spotlight".
 */
import './widgets.css';

export function Flourish({
  color,
  width = 72,
  height = 18,
}: {
  /** Base color, rendered at 0.7 alpha. Defaults to the accent. */
  color?: string;
  width?: number;
  height?: number;
}) {
  const c = color ?? 'var(--accent)';
  const cx = width / 2;
  const cy = height / 2;
  const r = 3.2;

  const tendril = (dir: 1 | -1) => {
    const x0 = cx + dir * (r + 2);
    const x1 = cx + dir * (cx - 3);
    return {
      d: `M ${x0} ${cy} C ${x0 + dir * 10} ${cy} ${x1 - dir * 14} ${cy - 6} ${
        x1 - dir * 4
      } ${cy - 6} C ${x1 + dir * 2} ${cy - 6} ${x1} ${cy - 1} ${x1 - dir * 4} ${
        cy - 1
      }`,
      dotX: x1 - dir * 4,
    };
  };

  const left = tendril(-1);
  const right = tendril(1);

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className="flourish"
      aria-hidden
    >
      <g opacity={0.7}>
        <path
          d={`M ${cx} ${cy - r} L ${cx + r} ${cy} L ${cx} ${cy + r} L ${
            cx - r
          } ${cy} Z`}
          fill={c}
        />
        <path
          d={left.d}
          fill="none"
          stroke={c}
          strokeWidth={1.1}
          strokeLinecap="round"
        />
        <circle cx={left.dotX} cy={cy - 1} r={1.3} fill={c} />
        <path
          d={right.d}
          fill="none"
          stroke={c}
          strokeWidth={1.1}
          strokeLinecap="round"
        />
        <circle cx={right.dotX} cy={cy - 1} r={1.3} fill={c} />
      </g>
    </svg>
  );
}
