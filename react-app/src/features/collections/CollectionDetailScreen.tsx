/**
 * CollectionDetailScreen — faithful port of Flutter's collection_detail_screen.dart.
 * Route: /collections/:id
 * Shows collection icon, uppercase mono title, and card count pill in the header,
 * with cards filtered by collection id (or system content type).
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { CaretLeft, Folder } from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { api } from '../../api/client';
import type { Card, Collection } from '../../api/types';
import { ContentType } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import { EmptyState } from '../../ui/feedback';
import { LoadingTiles } from '../../ui/loading-tiles';
import { CollectionsSpot } from '../../ui/spot-art';
import CardTile from '../library/CardTile';
import './collections.css';

function getCollectionAccent(c?: Collection | null): { color: string; Icon: Icon } {
  if (!c) {
    return { color: '#8A5A3C', Icon: Folder };
  }
  const st = c.system_type;
  if (!c.is_custom && st && (Object.values(ContentType) as string[]).includes(st)) {
    const a = contentAccent(st as ContentType);
    return { color: a.color, Icon: a.Icon };
  }
  return { color: '#8A5A3C', Icon: Folder };
}

export default function CollectionDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const collectionId = id ?? '';

  const [collection, setCollection] = useState<Collection | null>(null);
  const [cards, setCards] = useState<Card[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [cols, setCols] = useState(2);
  const gridRef = useRef<HTMLDivElement>(null);

  // Responsive column count matching Flutter's (width / 200).floor().clamp(2, 5)
  useEffect(() => {
    const updateCols = () => {
      const w = gridRef.current?.getBoundingClientRect().width ?? window.innerWidth;
      setCols(Math.min(5, Math.max(2, Math.floor(w / 200))));
    };
    updateCols();
    window.addEventListener('resize', updateCols);
    return () => window.removeEventListener('resize', updateCols);
  }, []);

  const loadData = useCallback(async () => {
    if (!collectionId) return;
    setLoading(true);
    try {
      // Load collections list to resolve name, type, and count
      const collections = await api.listCollections().catch(() => []);
      const matched = collections.find((c) => c.id === collectionId) ?? null;
      setCollection(matched);

      let fetchedCards: Card[];
      // Real backend UUID (> 10 chars)
      if (collectionId.length > 10) {
        fetchedCards = await api.listCards({ collection_id: collectionId });
      } else if (
        matched?.system_type &&
        (Object.values(ContentType) as string[]).includes(matched.system_type)
      ) {
        fetchedCards = await api.listCards({
          content_type: matched.system_type as ContentType,
        });
      } else {
        fetchedCards = await api.listCards();
      }
      setCards(fetchedCards);
    } catch {
      setCards([]);
    } finally {
      setLoading(false);
    }
  }, [collectionId]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  const handleDelete = useCallback(
    (cardId: string) => {
      setCards((prev) => (prev ? prev.filter((c) => c.card_id !== cardId) : []));
      api.deleteCard(cardId).catch(() => {});
    },
    [],
  );

  const accent = getCollectionAccent(collection);
  const title = (collection?.name ?? (collectionId || 'Collection')).toUpperCase();
  const cardCount = cards?.length ?? collection?.card_count ?? 0;

  return (
    <main className="page">
      <header className="collection-detail-header">
        <div className="collection-detail-title-row">
          <button
            type="button"
            className="back-btn"
            onClick={() => navigate('/collections')}
            aria-label="Back to folders"
          >
            <CaretLeft size={18} weight="bold" />
          </button>
          <accent.Icon
            size={18}
            color={accent.color}
            weight={collection?.is_custom ? 'fill' : 'regular'}
          />
          <h1 className="collection-detail-title">{title}</h1>
        </div>
        <span className="collection-detail-count">{cardCount}</span>
      </header>

      {loading ? (
        <LoadingTiles count={6} />
      ) : !cards || cards.length === 0 ? (
        <EmptyState
          title="Nothing here"
          message="Cards you save will appear here once processed."
          art={<CollectionsSpot />}
        />
      ) : (
        <div
          className="card-grid"
          ref={gridRef}
          style={{ gridTemplateColumns: `repeat(${cols}, 1fr)` }}
        >
          {cards.map((card) => (
            <CardTile
              key={card.card_id}
              card={card}
              onTap={() => navigate(`/reader/${encodeURIComponent(card.card_id)}`)}
              onDelete={() => handleDelete(card.card_id)}
            />
          ))}
        </div>
      )}
    </main>
  );
}
