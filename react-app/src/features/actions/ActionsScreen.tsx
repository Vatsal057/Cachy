import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowClockwise,
  ArrowLineUpRight,
  CaretDown,
  Check,
  Warning,
} from 'phosphor-react';
import { api, friendlyError } from '../../api/client';
import type { ActionItem } from '../../api/types';
import { ContentType } from '../../api/types';
import { contentAccent } from '../../ui/content-accent';
import './actions.css';

// The Actions hub — mirrors Flutter's actions_screen.dart: every followed
// to-do grouped by its source card, filter pills, collapsible sections,
// circle checkboxes, and the content-type tag pill per item.

interface ActionGroup {
  cardId: string;
  title: string;
  contentType: ContentType;
  followed: boolean;
  items: ActionItem[];
}

type FilterTab = 'all' | 'todo' | 'done';

function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(alpha * 255)
    .toString(16)
    .padStart(2, '0');
  return `${hex}${a}`;
}

// Spot illustration — transcribes Flutter's ActionsSpot painter.
function ActionsSpotArt() {
  const c = 'var(--ink-muted)';
  const rows = [11, 35, 59];
  return (
    <svg width={112} height={70} viewBox="0 0 112 70" aria-hidden>
      <g
        stroke={c}
        strokeOpacity={0.55}
        strokeWidth={1.7}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      >
        {rows.map((y, i) => (
          <g key={y}>
            <rect x={19} y={y - 9} width={18} height={18} rx={4} />
            {i === 0 ? (
              <path d={`M 24 ${y} L 27 ${y + 5} L 34 ${y - 6}`} />
            ) : null}
            <line
              x1={46}
              y1={y}
              x2={46 + (i === 1 ? 30 : 44)}
              y2={y}
            />
          </g>
        ))}
      </g>
    </svg>
  );
}

function FilterPill({
  label,
  selected,
  onTap,
}: {
  label: string;
  selected: boolean;
  onTap: () => void;
}) {
  return (
    <button
      className={'ax-pill' + (selected ? ' active' : '')}
      onClick={onTap}
    >
      {label}
    </button>
  );
}

function ActionItemCard({
  item,
  contentType,
  pending,
  onToggle,
}: {
  item: ActionItem;
  contentType: ContentType;
  pending: boolean;
  onToggle: () => void;
}) {
  const accent = contentAccent(contentType);
  const TagIcon = accent.Icon;
  return (
    <button
      className="ax-item"
      onClick={onToggle}
      disabled={pending}
      style={
        {
          '--ax-check-fill': accent.color,
          '--ax-hover-border': withAlpha(accent.color, 0.45),
          '--ax-hover-shadow': withAlpha(accent.color, 0.12),
        } as React.CSSProperties
      }
    >
      <span className={'ax-check' + (item.done ? ' done' : '')}>
        {item.done ? <Check size={13} weight="bold" /> : null}
      </span>
      <span className={'ax-item-text' + (item.done ? ' done' : '')}>
        {item.text}
      </span>
      <span className="ax-tag">
        <TagIcon size={11} />
        <span>{accent.label.toUpperCase()}</span>
      </span>
    </button>
  );
}

function GroupSection({
  group,
  items,
  pendingKeys,
  onToggle,
}: {
  group: ActionGroup;
  items: ActionItem[];
  pendingKeys: Set<string>;
  onToggle: (cardId: string, itemId: string) => void;
}) {
  const navigate = useNavigate();
  const [expanded, setExpanded] = useState(false);
  const accent = contentAccent(group.contentType);
  const toggle = () => setExpanded((e) => !e);
  return (
    <section className="ax-section">
      <div className="ax-head">
        <button
          type="button"
          className="ax-head-main"
          onClick={toggle}
          aria-expanded={expanded}
          aria-label={`${group.title} — ${expanded ? 'collapse' : 'expand'}`}
        >
          <span className="ax-dot" style={{ background: accent.color }} />
          <span className="ax-head-title">{group.title}</span>
          <span className="ax-count">{items.length}</span>
          <span className={'ax-caret' + (expanded ? '' : ' collapsed')}>
            <CaretDown size={16} />
          </span>
        </button>
        <button
          type="button"
          className="ax-open"
          aria-label="Open reel notes"
          title="Open reel notes"
          onClick={() => navigate(`/reader/${group.cardId}`)}
        >
          <ArrowLineUpRight size={15} />
        </button>
      </div>
      <div className={'ax-items' + (expanded ? '' : ' collapsed')}>
        <div className="ax-items-inner">
          <div className="ax-items-pad">
            {items.map((it) => (
              <ActionItemCard
                key={it.id}
                item={it}
                contentType={group.contentType}
                pending={pendingKeys.has(`${group.cardId}:${it.id}`)}
                onToggle={() => onToggle(group.cardId, it.id)}
              />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

export default function ActionsScreen() {
  const [groups, setGroups] = useState<ActionGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterTab>('all');
  const [pending, setPending] = useState<Set<string>>(new Set());

  const load = useCallback(async (withSpinner = true) => {
    if (withSpinner) setLoading(true);
    setError(null);
    try {
      const cards: any[] = await api.listCards({ limit: 200 });
      const gs: ActionGroup[] = [];
      for (const c of cards) {
        const ai = c?.action_items;
        const items: ActionItem[] = Array.isArray(ai?.items) ? ai.items : [];
        // Flutter's hub only shows cards the user *followed*.
        if (!ai?.followed || items.length === 0) continue;
        gs.push({
          cardId: String(c.card_id),
          title: String(c?.base?.one_liner || 'Saved Card'),
          contentType: (c?.base?.content_type as ContentType) ?? ContentType.OTHER,
          followed: true,
          items: items.map((it) => ({
            id: String(it.id),
            text: String(it.text),
            done: Boolean(it.done),
          })),
        });
      }
      setGroups(gs);
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const toggle = useCallback(
    async (cardId: string, itemId: string) => {
      const key = `${cardId}:${itemId}`;
      if (pending.has(key)) return;

      let nextItems: ActionItem[] = [];
      let followed = false;
      setGroups((prev) =>
        prev.map((g) => {
          if (g.cardId !== cardId) return g;
          followed = g.followed;
          nextItems = g.items.map((it) =>
            it.id === itemId ? { ...it, done: !it.done } : it,
          );
          return { ...g, items: nextItems };
        }),
      );

      setPending((p) => new Set(p).add(key));
      try {
        await api.patchCardActionItems(cardId, {
          followed,
          items: nextItems.map((it) => ({
            id: it.id,
            text: it.text,
            done: it.done,
          })),
        });
      } catch {
        setGroups((prev) =>
          prev.map((g) =>
            g.cardId !== cardId
              ? g
              : {
                  ...g,
                  items: g.items.map((it) =>
                    it.id === itemId ? { ...it, done: !it.done } : it,
                  ),
                },
          ),
        );
      } finally {
        setPending((p) => {
          const n = new Set(p);
          n.delete(key);
          return n;
        });
      }
    },
    [pending],
  );

  const sections = useMemo(() => {
    const out: { group: ActionGroup; items: ActionItem[] }[] = [];
    for (const g of groups) {
      const items =
        filter === 'all'
          ? g.items
          : filter === 'todo'
            ? g.items.filter((i) => !i.done)
            : g.items.filter((i) => i.done);
      if (items.length > 0) out.push({ group: g, items });
    }
    return out;
  }, [groups, filter]);

  return (
    <div className="page">
      <div className="ax-wrap">
        <p className="ax-eyebrow">CACHY</p>
        <h1 className="ax-title">{'Action\nItems'}</h1>

        <div className="ax-pills">
          <FilterPill
            label="All"
            selected={filter === 'all'}
            onTap={() => setFilter('all')}
          />
          <FilterPill
            label="To Do"
            selected={filter === 'todo'}
            onTap={() => setFilter('todo')}
          />
          <FilterPill
            label="Done"
            selected={filter === 'done'}
            onTap={() => setFilter('done')}
          />
          <button
            className="ax-refresh"
            onClick={() => void load(false)}
            disabled={loading}
            aria-label="Refresh"
            title="Refresh"
          >
            <ArrowClockwise size={20} />
          </button>
        </div>

        {loading ? (
          <div className="loading">
            <div className="spinner" aria-hidden />
          </div>
        ) : null}

        {!loading && error ? (
          <div className="ax-state">
            <Warning size={48} />
            <p>Couldn&apos;t load your actions</p>
            <button className="btn" onClick={() => void load()}>
              Retry
            </button>
          </div>
        ) : null}

        {!loading && !error && groups.length === 0 ? (
          <div className="ax-state">
            <ActionsSpotArt />
            <p>{'No actions yet.\nOpen a card and tap "Follow these actions".'}</p>
          </div>
        ) : null}

        {!loading && !error && groups.length > 0 && sections.length === 0 ? (
          <p className="ax-filter-empty">
            {filter === 'todo'
              ? 'No pending action items!'
              : 'No completed items yet.'}
          </p>
        ) : null}

        {!loading && !error
          ? sections.map(({ group, items }) => (
              <GroupSection
                key={group.cardId}
                group={group}
                items={items}
                pendingKeys={pending}
                onToggle={(cardId, itemId) => void toggle(cardId, itemId)}
              />
            ))
          : null}
      </div>
    </div>
  );
}
