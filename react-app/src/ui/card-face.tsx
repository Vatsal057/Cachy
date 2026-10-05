/**
 * CardFace — port of Flutter's ui/core/widgets/card_face.dart.
 * A card's "real face": the keyframe/thumbnail. When the image is missing or
 * fails to load it degrades to a calm content-type accent panel — never an
 * empty box, never a crash.
 */
import { useState } from 'react';
import type { Icon } from 'phosphor-react';
import { ContentType } from '../api/types';
import { contentAccent } from './content-accent';
import './widgets.css';

/**
 * The accent fallback face: gradient wash (top-left rich → bottom-right
 * fades), an oversized rotated background icon, and a centred icon.
 */
export function AccentFace({
  color,
  Icon,
  dim = false,
}: {
  color: string;
  Icon: Icon;
  /** Dimmed variant used as the image placeholder (Flutter: op = 0.55). */
  dim?: boolean;
}) {
  return (
    <div className={`accent-face${dim ? ' dim' : ''}`} aria-hidden>
      <div
        className="accent-wash"
        style={{
          background: `linear-gradient(to bottom right, ${color}59, ${color}1a)`,
        }}
      />
      <Icon className="accent-bg-icon" size={120} color={color} weight="regular" />
      <span className="accent-fg-icon">
        <Icon size={34} color={color} weight="regular" />
      </span>
    </div>
  );
}

export function CardFace({
  thumbnail,
  contentType,
  resolveUrl,
  alt = '',
  className,
}: {
  /** Media reference (e.g. "/media/{id}/thumb.jpg"); null/empty → accent face. */
  thumbnail?: string | null;
  contentType: ContentType;
  /** Mirrors Dart's ApiClient.resolveMedia. */
  resolveUrl: (ref: string) => string;
  alt?: string;
  className?: string;
}) {
  const accent = contentAccent(contentType);
  const [failed, setFailed] = useState(false);
  const url = thumbnail && !failed ? resolveUrl(thumbnail) : null;

  return (
    <div className={`card-face${className ? ` ${className}` : ''}`}>
      {/* Accent wash sits behind: the loading placeholder, and the fallback
          when the image errors (Flutter's placeholder / errorWidget). */}
      <AccentFace color={accent.color} Icon={accent.Icon} dim={url != null} />
      {url ? (
        <img
          src={url}
          alt={alt}
          className="card-face-img"
          onError={() => setFailed(true)}
        />
      ) : null}
    </div>
  );
}
