/**
 * ContextMenu — port of Flutter's ui/core/widgets/context_menu.dart.
 * Desktop right-click / mobile long-press context menu for library and
 * highlight cards. The action *sets* are assembled by pure builder functions;
 * the ContextMenu component renders at an anchor point and runs the selected
 * action safely (a throwing action surfaces an error toast, never a crash).
 */
import { useEffect, useRef, useState } from 'react';
import {
  ArrowSquareOut,
  Copy,
  PlusCircle,
  TextT,
  Trash,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import './widgets.css';

/** A single entry in a card context menu. Pure data. */
export interface ContextMenuAction {
  label: string;
  icon: Icon;
  onSelected: () => void | Promise<void>;
  /** Tints the entry with the error color (e.g. "Delete"). */
  destructive?: boolean;
}

/**
 * Assemble the context-menu action set for a content card tile.
 * Order is always: Open, Open in New Tab (desktop only), Copy Link, Delete.
 */
export function buildCardMenuActions({
  isDesktopPlatform,
  onOpen,
  onOpenNewTab,
  onCopyLink,
  onDelete,
}: {
  isDesktopPlatform: boolean;
  onOpen: () => void | Promise<void>;
  onOpenNewTab: () => void | Promise<void>;
  onCopyLink: () => void | Promise<void>;
  onDelete: () => void | Promise<void>;
}): ContextMenuAction[] {
  return [
    { label: 'Open', icon: ArrowSquareOut, onSelected: onOpen },
    ...(isDesktopPlatform
      ? [
          {
            label: 'Open in New Tab',
            icon: PlusCircle,
            onSelected: onOpenNewTab,
          } as ContextMenuAction,
        ]
      : []),
    { label: 'Copy Link', icon: Copy, onSelected: onCopyLink },
    { label: 'Delete', icon: Trash, onSelected: onDelete, destructive: true },
  ];
}

/** Assemble the context-menu action set for a highlight card. */
export function buildHighlightMenuActions({
  onCopyText,
  onDelete,
}: {
  onCopyText: () => void | Promise<void>;
  onDelete: () => void | Promise<void>;
}): ContextMenuAction[] {
  return [
    { label: 'Copy Text', icon: TextT, onSelected: onCopyText },
    { label: 'Delete', icon: Trash, onSelected: onDelete, destructive: true },
  ];
}

const MENU_W = 220;
const MENU_PAD = 8;

/**
 * Floating menu anchored at an (x, y) viewport point. Tapping outside or
 * pressing Escape dismisses without running any action. If the selected
 * action throws, onError receives `Could not {label}: {error}`.
 */
export function ContextMenu({
  x,
  y,
  actions,
  onClose,
  onError,
}: {
  x: number;
  y: number;
  actions: ContextMenuAction[];
  onClose: () => void;
  onError?: (message: string) => void;
}) {
  const [pos] = useState(() => ({
    left: Math.min(Math.max(x, MENU_PAD), window.innerWidth - MENU_W - MENU_PAD),
    top: Math.min(
      Math.max(y, MENU_PAD),
      window.innerHeight - actions.length * 44 - MENU_PAD - 16,
    ),
  }));
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const run = async (action: ContextMenuAction) => {
    onClose();
    try {
      await action.onSelected();
    } catch (error) {
      onError?.(`Could not ${action.label.toLowerCase()}: ${error}`);
    }
  };

  return (
    <>
      <div
        className="ctx-menu-scrim"
        aria-hidden
        onClick={onClose}
        onContextMenu={(e) => {
          e.preventDefault();
          onClose();
        }}
      />
      <div
        ref={menuRef}
        className="ctx-menu"
        role="menu"
        style={{ left: pos.left, top: pos.top, width: MENU_W }}
      >
        {actions.map((a) => {
          const AIcon = a.icon;
          return (
            <button
              key={a.label}
              type="button"
              role="menuitem"
              className={`ctx-item${a.destructive ? ' destructive' : ''}`}
              onClick={() => void run(a)}
            >
              <AIcon size={18} weight="regular" aria-hidden />
              <span>{a.label}</span>
            </button>
          );
        })}
      </div>
    </>
  );
}
