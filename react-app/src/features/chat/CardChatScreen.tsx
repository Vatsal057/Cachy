/**
 * Ask-the-card screen (docs/13) — port of Flutter's reader/views/chat_screen.dart
 * + chat_view_model.dart. A grounded chat over one card; route
 * /reader/:id/chat. An optional `?seed=` opening question is auto-sent when
 * there is no saved conversation to restore.
 */
import { useEffect, useState } from 'react';
import { useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { api } from '../../api/client';
import { goBack } from './ChatAppBar';
import { ChatThreadView } from './ChatThreadView';
import { useChatThread } from './useChatThread';
import './chat.css';

export default function CardChatScreen() {
  const { id = '' } = useParams<{ id: string }>();
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const location = useLocation();

  const seed = params.get('seed') ?? undefined;
  const stateTitle = (location.state as { title?: string } | null)?.title;

  // The card's one-liner is the header title (Flutter passes it in; here it
  // comes from router state when available, otherwise a best-effort fetch).
  const [fetched, setFetched] = useState<{ id: string; title: string } | null>(null);
  useEffect(() => {
    if (stateTitle || !id) return;
    let cancelled = false;
    api
      .getCard(id)
      .then((card) => {
        if (!cancelled) setFetched({ id, title: card.base?.one_liner ?? '' });
      })
      .catch(() => {
        /* header falls back to "Ask this card" */
      });
    return () => {
      cancelled = true;
    };
  }, [id, stateTitle]);

  const title = (stateTitle ?? (fetched?.id === id ? fetched.title : '')).trim();

  const thread = useChatThread({
    threadKey: id,
    loadHistory: () => api.chatHistory(id),
    ask: async (messages) => ({ reply: await api.chat(id, messages) }),
    seed,
  });

  return (
    <ChatThreadView
      title={title || 'Ask this card'}
      onBack={() => goBack(navigate, location, `/reader/${encodeURIComponent(id)}`)}
      thread={thread}
      placeholder="Ask about this card"
      empty={
        <p className="chat-empty-text">
          Ask anything about this card — ingredients, steps, the gist…
        </p>
      }
    />
  );
}
