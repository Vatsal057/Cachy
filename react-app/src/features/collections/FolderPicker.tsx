/**
 * Bulk "Move to Folder" picker — port of folder_picker_sheet.dart.
 * Lists the user's folders plus "New folder…" and "Remove from folders".
 * Presented by the library's selection flow; moving is the caller's job via
 * onPick, matching the Flutter sheet's contract.
 */
import { useEffect, useState } from 'react';
import { Folder, FolderMinus, FolderPlus } from 'phosphor-react';
import { api } from '../../api/client';
import type { Collection } from '../../api/types';
import { Modal } from '../../ui/feedback';
import './collections.css';

export function FolderPickerSheet({
  onClose,
  onPick,
}: {
  onClose: () => void;
  /** (collectionId, label): collectionId null = remove from all folders. */
  onPick: (collectionId: string | null, label: string | null) => void;
}) {
  const [folders, setFolders] = useState<Collection[] | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [name, setName] = useState('');
  const [createError, setCreateError] = useState('');

  useEffect(() => {
    let alive = true;
    api
      .listCollections()
      .then((f) => {
        if (alive) setFolders(f);
      })
      .catch(() => {
        if (alive) setFolders([]);
      });
    return () => {
      alive = false;
    };
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  async function createAndPick() {
    const trimmed = name.trim();
    if (!trimmed) {
      setShowCreate(false);
      return;
    }
    try {
      const created = await api.createCollection(trimmed);
      onPick(created.id, created.name);
    } catch {
      setCreateError('Could not create folder');
    }
  }

  return (
    <>
      <div className="sheet-backdrop" onClick={onClose}>
        <div
          className="sheet folder-picker"
          role="dialog"
          aria-modal="true"
          aria-label="Move to folder"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="sheet-handle" aria-hidden />
          <h2 className="folder-picker-title">Move to folder</h2>
          {folders === null ? (
            <div className="loading">
              <div className="spinner" aria-hidden />
            </div>
          ) : (
            <div className="folder-picker-list">
              {folders.map((f) => (
                <button
                  key={f.id}
                  type="button"
                  className="folder-picker-row"
                  onClick={() => onPick(f.id, f.name)}
                >
                  <Folder size={20} aria-hidden />
                  <span>{f.name}</span>
                </button>
              ))}
              <div className="folder-picker-divider" aria-hidden />
              <button
                type="button"
                className="folder-picker-row primary"
                onClick={() => {
                  setName('');
                  setCreateError('');
                  setShowCreate(true);
                }}
              >
                <FolderPlus size={20} aria-hidden />
                <span>New folder…</span>
              </button>
              {folders.length > 0 && (
                <button
                  type="button"
                  className="folder-picker-row"
                  onClick={() => onPick(null, null)}
                >
                  <FolderMinus size={20} aria-hidden />
                  <span>Remove from folders</span>
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {showCreate && (
        <Modal
          title="New folder"
          onClose={() => setShowCreate(false)}
          actions={
            <>
              <button type="button" className="fb-text-btn" onClick={() => setShowCreate(false)}>
                Cancel
              </button>
              <button type="button" className="fb-filled-btn" onClick={() => void createAndPick()}>
                Create
              </button>
            </>
          }
        >
          <input
            className="input"
            autoFocus
            placeholder="Folder name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void createAndPick();
            }}
            aria-label="Folder name"
          />
          {createError && <p className="fb-dialog-error">{createError}</p>}
        </Modal>
      )}
    </>
  );
}
