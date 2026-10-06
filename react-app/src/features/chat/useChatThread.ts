/**
 * Conversation state shared by the card chat and the library chat (ports of
 * Flutter's ChatViewModel / LibraryChatViewModel). The server is stateless per
 * turn: this hook owns the conversation and replays the whole history on every
 * send. Saved history is restored on entry; an optional `seed` is auto-sent
 * only when there is nothing to restore.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ChatMessage, LibrarySource } from '../../api/types';
import { CHAT_COPY, describeFailure } from './chat-errors';
import type { Failure } from './chat-errors';

export interface ChatAnswer {
  reply: string;
  sources?: LibrarySource[];
}

export interface ChatThread {
  messages: ChatMessage[];
  /** Cards the latest answer was grounded on (library chat only). */
  sources: LibrarySource[];
  busy: boolean;
  /** Restoring saved history. */
  loading: boolean;
  failure: Failure | null;
  /** Last turn failed and the user message is still waiting for a reply. */
  canRetry: boolean;
  /** Returns false when the text was empty or a turn is already in flight. */
  send: (text: string) => boolean;
  retry: () => void;
}

interface Options {
  /** Identity of the conversation; changing it starts over. */
  threadKey: string;
  loadHistory: () => Promise<ChatMessage[]>;
  ask: (messages: ChatMessage[]) => Promise<ChatAnswer>;
  seed?: string;
}

export function useChatThread({ threadKey, loadHistory, ask, seed }: Options): ChatThread {
  const [messages, setMessagesState] = useState<ChatMessage[]>([]);
  const [sources, setSources] = useState<LibrarySource[]>([]);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<Failure | null>(null);

  const messagesRef = useRef<ChatMessage[]>([]);
  const busyRef = useRef(false);
  // Bumped on thread change / unmount so late responses are dropped.
  const generation = useRef(0);
  const loadRef = useRef(loadHistory);
  const askRef = useRef(ask);
  loadRef.current = loadHistory;
  askRef.current = ask;

  const setMessages = useCallback((next: ChatMessage[]) => {
    messagesRef.current = next;
    setMessagesState(next);
  }, []);

  const run = useCallback(async () => {
    const gen = generation.current;
    busyRef.current = true;
    setBusy(true);
    setFailure(null);
    setSources([]);
    try {
      const res = await askRef.current(messagesRef.current);
      if (gen !== generation.current) return;
      setMessages([...messagesRef.current, { role: 'assistant', content: res.reply }]);
      setSources(res.sources ?? []);
    } catch (err) {
      if (gen !== generation.current) return;
      setFailure(describeFailure(err, CHAT_COPY));
    }
    busyRef.current = false;
    setBusy(false);
  }, [setMessages]);

  const send = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (!trimmed || busyRef.current) return false;
      setMessages([...messagesRef.current, { role: 'user', content: trimmed }]);
      void run();
      return true;
    },
    [run, setMessages],
  );

  const retry = useCallback(() => {
    const last = messagesRef.current[messagesRef.current.length - 1];
    if (busyRef.current || !last || last.role !== 'user') return;
    void run();
  }, [run]);

  useEffect(() => {
    const gen = ++generation.current;
    setMessages([]);
    setSources([]);
    setFailure(null);
    busyRef.current = false;
    setBusy(false);
    setLoading(true);

    void (async () => {
      let saved: ChatMessage[] = [];
      try {
        saved = await loadRef.current();
      } catch {
        // Best-effort restore; a fresh conversation is fine.
      }
      if (gen !== generation.current) return;
      if (saved.length > 0) setMessages([...saved, ...messagesRef.current]);
      setLoading(false);
      if (messagesRef.current.length === 0 && seed && seed.trim()) send(seed);
    })();

    return () => {
      generation.current++;
    };
  }, [threadKey, seed, send, setMessages]);

  const last = messages[messages.length - 1];
  const canRetry = !busy && !!failure && !failure.quota && last?.role === 'user';

  return { messages, sources, busy, loading, failure, canRetry, send, retry };
}
