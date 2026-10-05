/**
 * Long-press hook — the web equivalent of Flutter's GestureDetector.onLongPress
 * used across the reader (highlight creation on paragraphs, bullets, steps).
 *
 * Fires `onLongPress` after 550ms of continuous press, suppresses the native
 * context menu, and vibrates briefly (the web stand-in for HapticFeedback).
 * `consumeTap()` reports whether the long-press fired, so a tap handler on the
 * same element (e.g. step/checklist toggles) can skip the tap that follows a
 * long-press — mirroring Flutter, where a long-press never also triggers onTap.
 */
import { useCallback, useRef } from 'react';
import type { MouseEvent } from 'react';

const LONG_PRESS_MS = 550;

export function useLongPress(onLongPress?: () => void) {
  const timer = useRef<number | null>(null);
  const fired = useRef(false);

  const clear = useCallback(() => {
    if (timer.current !== null) {
      window.clearTimeout(timer.current);
      timer.current = null;
    }
  }, []);

  const onPointerDown = useCallback(() => {
    fired.current = false;
    clear();
    if (!onLongPress) return;
    timer.current = window.setTimeout(() => {
      timer.current = null;
      fired.current = true;
      try {
        navigator.vibrate?.(10);
      } catch {
        /* vibrate unsupported — the toast still confirms the save */
      }
      onLongPress();
    }, LONG_PRESS_MS);
  }, [clear, onLongPress]);

  const onContextMenu = useCallback(
    (e: MouseEvent) => {
      if (onLongPress) e.preventDefault();
    },
    [onLongPress],
  );

  /** True when the most recent press ended in a long-press. */
  const consumeTap = useCallback(() => {
    const was = fired.current;
    fired.current = false;
    return was;
  }, []);

  return {
    onPointerDown,
    onPointerUp: clear,
    onPointerLeave: clear,
    onPointerCancel: clear,
    onContextMenu,
    consumeTap,
  };
}
