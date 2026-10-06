/**
 * Port of Flutter's RabbitHoleViewModel (docs/14): the ordered trail of
 * explored steps for one card + root topic. Saved trails are restored on
 * entry; otherwise the first dive starts automatically. Every dive replays the
 * trail so the exploration stays coherent.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { RabbitHoleStep } from '../../api/types';
import { RABBIT_HOLE_COPY, describeFailure } from '../chat/chat-errors';
import type { Failure } from '../chat/chat-errors';

export interface RabbitHole {
  /** Explored trail, oldest → newest. */
  steps: RabbitHoleStep[];
  /** The deepest step reached — what the screen renders. */
  current: RabbitHoleStep | null;
  busy: boolean;
  /** Restoring a saved trail. */
  loading: boolean;
  failure: Failure | null;
  /** Topic currently being fetched (pending breadcrumb). */
  pendingTopic: string | null;
  canRetry: boolean;
  dive: (topic: string) => void;
  retry: () => void;
  /** Breadcrumb tap: drop everything deeper than `index`. */
  jumpTo: (index: number) => void;
}

export function useRabbitHole(cardId: string, seed: string): RabbitHole {
  const [steps, setStepsState] = useState<RabbitHoleStep[]>([]);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<Failure | null>(null);
  const [pendingTopic, setPendingTopic] = useState<string | null>(null);
  const [failedTopic, setFailedTopic] = useState<string | null>(null);

  const stepsRef = useRef<RabbitHoleStep[]>([]);
  const busyRef = useRef(false);
  const failedRef = useRef<string | null>(null);
  const generation = useRef(0);
  // The topic the journey started from — the persistence key.
  const root = seed.trim();

  const setSteps = useCallback((next: RabbitHoleStep[]) => {
    stepsRef.current = next;
    setStepsState(next);
  }, []);

  const setFailed = useCallback((topic: string | null) => {
    failedRef.current = topic;
    setFailedTopic(topic);
  }, []);

  const dive = useCallback(
    async (topic: string) => {
      const trimmed = topic.trim();
      if (!trimmed || busyRef.current) return;
      const gen = generation.current;

      busyRef.current = true;
      setBusy(true);
      setFailure(null);
      setFailed(null);
      setPendingTopic(trimmed);

      const trail = stepsRef.current.map((s) => s.topic);
      try {
        const step = await api.exploreRabbitHole(cardId, trimmed, trail, root);
        if (gen !== generation.current) return;
        setSteps([...stepsRef.current, step]);
      } catch (err) {
        if (gen !== generation.current) return;
        const f = describeFailure(err, RABBIT_HOLE_COPY);
        setFailure(f);
        setFailed(f.quota ? null : trimmed);
      }
      busyRef.current = false;
      setBusy(false);
      setPendingTopic(null);
    },
    [cardId, root, setFailed, setSteps],
  );

  const retry = useCallback(() => {
    const topic = failedRef.current;
    if (topic) void dive(topic);
  }, [dive]);

  const jumpTo = useCallback(
    (index: number) => {
      const cur = stepsRef.current;
      if (busyRef.current || index < 0 || index >= cur.length - 1) return;
      setSteps(cur.slice(0, index + 1));
      setFailure(null);
      setFailed(null);
    },
    [setFailed, setSteps],
  );

  useEffect(() => {
    const gen = ++generation.current;
    setSteps([]);
    setFailure(null);
    setFailed(null);
    setPendingTopic(null);
    busyRef.current = false;
    setBusy(false);

    if (!root) {
      setLoading(false);
      return;
    }
    setLoading(true);

    void (async () => {
      let saved: RabbitHoleStep[] = [];
      try {
        saved = await api.rabbitHoleHistory(cardId, root);
      } catch {
        // Best-effort restore; a fresh exploration is fine.
      }
      if (gen !== generation.current) return;
      if (saved.length > 0) setSteps(saved);
      setLoading(false);
      if (stepsRef.current.length === 0) void dive(seed);
    })();

    return () => {
      generation.current++;
    };
  }, [cardId, root, seed, dive, setFailed, setSteps]);

  return {
    steps,
    current: steps.length > 0 ? steps[steps.length - 1] : null,
    busy,
    loading,
    failure,
    pendingTopic,
    canRetry: failedTopic !== null && !busy,
    dive: (topic) => void dive(topic),
    retry,
    jumpTo,
  };
}
