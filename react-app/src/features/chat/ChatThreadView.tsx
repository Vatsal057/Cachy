/**
 * The conversation UI shared by "Ask this card" and "Ask your library"
 * (Flutter's _ChatView / _LibraryChatView, which are identical apart from the
 * title, empty state, composer hint and the library's source chips).
 */
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { KeyboardEvent, ReactNode } from 'react';
import { ArrowClockwise, PaperPlaneRight } from 'phosphor-react';
import { AlertStrip } from '../../ui/feedback';
import { RichInlineText } from '../../ui/rich-text';
import { ChatAppBar } from './ChatAppBar';
import type { ChatThread } from './useChatThread';
import './chat.css';

/** Textarea grows to this many lines, then scrolls (Flutter maxLines: 4). */
const MAX_COMPOSER_HEIGHT = 120;

function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  );
}

export function ChatThreadView({
  title,
  onBack,
  thread,
  empty,
  placeholder,
  aboveComposer,
}: {
  title: string;
  onBack: () => void;
  thread: ChatThread;
  /** Shown when there are no messages yet. */
  empty: ReactNode;
  placeholder: string;
  /** Slot between the messages and the composer (library source chips). */
  aboveComposer?: ReactNode;
}) {
  const { messages, busy, loading, failure, canRetry } = thread;
  const [text, setText] = useState('');
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const isEmpty = messages.length === 0;

  // Keep the newest message (or the typing indicator) in view.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTo({
      top: el.scrollHeight,
      behavior: prefersReducedMotion() ? 'auto' : 'smooth',
    });
  }, [messages.length, busy, failure, loading]);

  // Auto-grow the composer.
  useLayoutEffect(() => {
    const el = inputRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, MAX_COMPOSER_HEIGHT)}px`;
  }, [text]);

  const submit = () => {
    if (!text.trim() || busy) return;
    if (thread.send(text)) {
      setText('');
      inputRef.current?.focus();
    }
  };

  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key !== 'Enter' || e.shiftKey || e.nativeEvent.isComposing) return;
    e.preventDefault();
    submit();
  };

  const canSend = text.trim().length > 0 && !busy;

  return (
    <div className="chat-screen">
      <ChatAppBar title={title} onBack={onBack} />

      <div className="chat-body">
        {loading && isEmpty ? (
          <div className="chat-center" role="status" aria-label="Loading conversation">
            <span className="spinner chat-spinner-lg" />
          </div>
        ) : isEmpty ? (
          <div className="chat-center">
            <div className="chat-empty">{empty}</div>
          </div>
        ) : (
          <div
            className="chat-scroll"
            ref={scrollRef}
            role="log"
            aria-live="polite"
            aria-relevant="additions"
          >
            <div className="chat-column chat-list">
              {messages.map((m, i) => (
                <div
                  key={i}
                  className={`chat-row ${m.role === 'user' ? 'user' : 'assistant'}`}
                >
                  <div
                    className={`chat-bubble ${m.role === 'user' ? 'user' : 'assistant'}`}
                  >
                    <RichInlineText text={m.content} />
                  </div>
                </div>
              ))}
              {busy ? (
                <div className="chat-row assistant">
                  <div className="chat-typing" role="status" aria-label="Thinking">
                    <span className="spinner chat-spinner-sm" />
                  </div>
                </div>
              ) : null}
            </div>
          </div>
        )}
      </div>

      <div className="chat-footer">
        {aboveComposer}
        {failure ? (
          <div className="chat-column chat-feedback">
            {failure.quota ? (
              <AlertStrip kind="warning" message={failure.message} />
            ) : (
              <div className="chat-error-row" role="alert">
                <span className="chat-error-text">{failure.message}</span>
                {canRetry ? (
                  <button type="button" className="chat-retry" onClick={thread.retry}>
                    <ArrowClockwise size={16} weight="regular" aria-hidden />
                    Try again
                  </button>
                ) : null}
              </div>
            )}
          </div>
        ) : null}

        <div className="chat-composer">
          <div className="chat-column chat-composer-row">
            <textarea
              ref={inputRef}
              className="chat-input"
              rows={1}
              value={text}
              placeholder={placeholder}
              aria-label={placeholder}
              enterKeyHint="send"
              onChange={(e) => setText(e.target.value)}
              onKeyDown={onKeyDown}
            />
            <button
              type="button"
              className="chat-send"
              onClick={submit}
              disabled={!canSend}
              aria-label="Send"
            >
              <PaperPlaneRight size={24} weight="regular" aria-hidden />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
