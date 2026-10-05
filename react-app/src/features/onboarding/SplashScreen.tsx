import { useEffect, useRef } from 'react';
import { CachyGlyphSvg } from './OnboardingScreen';
import './Onboarding.css';

/**
 * The launch moment: the brand glyph "catches" a falling reel, then the
 * wordmark draws in. Plays over the charcoal ground, ~1.3 s, then onDone
 * fires. Tappable to skip. (Port of Flutter's SplashScreen.)
 */
export default function SplashScreen({ onDone }: { onDone: () => void }) {
  const doneRef = useRef(false);
  const onDoneRef = useRef(onDone);
  onDoneRef.current = onDone;

  useEffect(() => {
    const finish = () => {
      if (doneRef.current) return;
      doneRef.current = true;
      onDoneRef.current();
    };
    const t = setTimeout(finish, 1300);
    return () => clearTimeout(t);
  }, []);

  const skip = () => {
    if (doneRef.current) return;
    doneRef.current = true;
    onDoneRef.current();
  };

  return (
    <div className="splash-root" onClick={skip} role="button" aria-label="Skip">
      <div className="splash-stack">
        <CachyGlyphSvg size={92} animateReel />
        <div className="splash-wordmark">cachy</div>
      </div>
    </div>
  );
}
