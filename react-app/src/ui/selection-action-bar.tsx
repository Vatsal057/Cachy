/**
 * SelectionActionBar — port of Flutter's
 * ui/core/widgets/selection_action_bar.dart.
 * A floating glass bulk-action bar shown while one or more library cards are
 * selected. Presentational only: takes a selectedCount plus action callbacks.
 */
import { Folder, Trash, X } from 'phosphor-react';
import { Glass } from './glass';
import './widgets.css';

export function SelectionActionBar({
  selectedCount,
  onDeleteSelected,
  onMoveToFolder,
  onClose,
}: {
  /** Number of currently selected cards, rendered as "{n} selected". */
  selectedCount: number;
  /** Invoked when the user activates "Delete Selected". */
  onDeleteSelected: () => void;
  /** Invoked when the user activates "Move to Folder". */
  onMoveToFolder: () => void;
  /** Invoked when the user clears the selection via the leading control. */
  onClose: () => void;
}) {
  return (
    <div className="selection-bar-wrap">
      <Glass radius={14} className="selection-bar">
        <button
          type="button"
          className="icon-btn"
          aria-label="Clear selection"
          title="Clear selection"
          onClick={onClose}
        >
          <X size={20} weight="regular" />
        </button>
        <span className="selection-count">
          {selectedCount} selected
        </span>
        <span className="selection-spacer" />
        <button
          type="button"
          className="bar-action"
          title="Move to Folder"
          onClick={onMoveToFolder}
        >
          <Folder size={18} weight="regular" aria-hidden />
          <span>Move to Folder</span>
        </button>
        <button
          type="button"
          className="bar-action danger"
          title="Delete Selected"
          onClick={onDeleteSelected}
        >
          <Trash size={18} weight="regular" aria-hidden />
          <span>Delete Selected</span>
        </button>
      </Glass>
    </div>
  );
}
