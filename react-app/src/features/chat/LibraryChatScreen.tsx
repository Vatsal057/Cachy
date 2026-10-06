/**
 * Ask-your-library screen (docs/09) — port of Flutter's
 * library/views/library_chat_screen.dart + library_chat_view_model.dart.
 * Grounded chat across every saved card; the cards behind the latest answer
 * show as tappable source chips. Route /library/chat; an optional `?seed=`
 * question is auto-sent when there is no saved conversation to restore.
 */
import { Article } from 'phosphor-react';
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom';
import { api } from '../../api/client';
import { ChatSpot } from '../../ui/spot-art';
import { goBack } from './ChatAppBar';
import { ChatThreadView } from './ChatThreadView';
import { useChatThread } from './useChatThread';
import './chat.css';

export default function LibraryChatScreen() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const location = useLocation();
  const seed = params.get('seed') ?? undefined;

  const thread = useChatThread({
    threadKey: 'library',
    loadHistory: () => api.libraryChatHistory(),
    ask: (messages) => api.libraryChat(messages),
    seed,
  });

  const sources =
    thread.sources.length > 0 && !thread.busy ? (
      <div className="chat-column chat-sources">
        <p className="chat-sources-label">SOURCES</p>
        <div className="chat-sources-wrap">
          {thread.sources.map((s) => (
            <button
              key={s.card_id}
              type="button"
              className="chat-chip"
              onClick={() => navigate(`/reader/${encodeURIComponent(s.card_id)}`)}
            >
              <Article size={16} weight="regular" aria-hidden />
              <span className="chat-chip-label">{s.one_liner || 'Card'}</span>
            </button>
          ))}
        </div>
      </div>
    ) : null;

  return (
    <ChatThreadView
      title="Ask your library"
      onBack={() => goBack(navigate, location, '/library')}
      thread={thread}
      placeholder="Ask your library"
      aboveComposer={sources}
      empty={
        <>
          <ChatSpot />
          <p className="chat-empty-text chat-empty-spaced">
            Ask anything across your saved cards — "what workouts have I saved?",
            "summarise the budgeting tips"…
          </p>
        </>
      }
    />
  );
}
