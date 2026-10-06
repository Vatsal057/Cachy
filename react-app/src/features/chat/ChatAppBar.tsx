/**
 * Top bar shared by the three AI screens (Flutter AppBar with a title and the
 * standard "AI-generated, may contain errors" label underneath).
 */
import { ArrowLeft } from 'phosphor-react';
import type { NavigateFunction, Location } from 'react-router-dom';
import './chat.css';

export const AI_NOTE = 'AI-GENERATED · MAY CONTAIN ERRORS';

export function ChatAppBar({
  title,
  onBack,
}: {
  title: string;
  onBack: () => void;
}) {
  return (
    <header className="chat-appbar">
      <button type="button" className="chat-back" onClick={onBack} aria-label="Back">
        <ArrowLeft size={24} weight="regular" aria-hidden />
      </button>
      <div className="chat-appbar-titles">
        <h1 className="chat-appbar-title" title={title}>
          {title}
        </h1>
        <p className="chat-appbar-note">{AI_NOTE}</p>
      </div>
    </header>
  );
}

/**
 * navigate(-1), except when this screen was the entry point (deep link /
 * reload) where there is nothing to go back to — then use `fallback`.
 */
export function goBack(navigate: NavigateFunction, location: Location, fallback: string) {
  if (location.key === 'default') navigate(fallback, { replace: true });
  else navigate(-1);
}
