/**
 * LoadingTiles — port of Flutter's ui/core/widgets/loading_tiles.dart.
 * Shimmer placeholder tiles for the library grid while the first load
 * resolves. Matches the real grid's shape so the transition to content
 * doesn't reflow. Static (no shimmer) under reduced motion.
 */
import { useMedia } from './use-media';
import './widgets.css';

export function LoadingTiles({ count = 6 }: { count?: number }) {
  // Flutter: context.motionEnabled gates the looping shimmer.
  const motionOK = !useMedia('(prefers-reduced-motion: reduce)');
  return (
    <div className="loading-tiles" aria-label="Loading">
      {Array.from({ length: count }).map((_, i) => (
        <div
          key={i}
          className={`loading-tile${motionOK ? ' shimmer' : ''}`}
          style={motionOK ? { animationDelay: `${i * 90}ms` } : undefined}
          aria-hidden
        />
      ))}
    </div>
  );
}
