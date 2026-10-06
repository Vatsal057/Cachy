/**
 * Maps a failed chat / rabbit-hole request to the copy Flutter shows
 * (chat_view_model.dart, rabbit_hole_view_model.dart). 429 — the daily AI
 * quota — has no Flutter counterpart, so it is flagged separately and the UI
 * renders it as a calm warning (no retry) instead of an error.
 */
import { ApiException, apiErrorMessage } from '../../api/client';

export interface Failure {
  message: string;
  /** Daily quota reached (HTTP 429): retrying today is pointless. */
  quota: boolean;
}

export interface FailureCopy {
  /** Shown for HTTP 503 ("the model is overloaded"). */
  busy: string;
  /** Shown for any other HTTP failure. */
  failed: string;
}

export const CHAT_COPY: FailureCopy = {
  busy: 'The AI is catching its breath — try again in a moment.',
  failed: "Couldn't get an answer. Try again.",
};

export const RABBIT_HOLE_COPY: FailureCopy = {
  busy: 'The rabbit hole is catching its breath — try again in a moment.',
  failed: "Couldn't explore that thread. Try again.",
};

const UNREACHABLE = "Couldn't reach the backend.";

export function describeFailure(err: unknown, copy: FailureCopy): Failure {
  if (err instanceof ApiException) {
    if (err.status === 429) return { message: apiErrorMessage(err), quota: true };
    if (err.status === 503) return { message: copy.busy, quota: false };
    if (err.status === 0) return { message: UNREACHABLE, quota: false };
    return { message: copy.failed, quota: false };
  }
  return { message: UNREACHABLE, quota: false };
}
