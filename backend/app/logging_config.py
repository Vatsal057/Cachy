"""Clean, colour-coded logging for the Cachy pipeline.

Replaces Python's default ``INFO:logger.name:message`` format with:

  11:42:03  INFO   worker       [card ab12] pipeline start · instagram
  11:42:08  WARN   extraction   ffmpeg not found; skipping audio extraction

Call ``configure_logging()`` once at startup. Safe to call multiple times
(idempotent — replaces formatters rather than stacking handlers).
"""

from __future__ import annotations

import logging
import sys

_RESET = "\033[0m"
_DIM   = "\033[2m"
_CYAN  = "\033[36m"

_LEVEL_FMT: dict[int, tuple[str, str]] = {
    logging.DEBUG:    ("DEBUG", "\033[90m"),
    logging.INFO:     ("INFO ", "\033[32m"),
    logging.WARNING:  ("WARN ", "\033[33m"),
    logging.ERROR:    ("ERROR", "\033[31m"),
    logging.CRITICAL: ("CRIT ", "\033[1;31m"),
}

# Third-party libraries whose INFO/DEBUG output is pure noise during development.
_QUIET_LOGGERS = (
    "yt_dlp",
    "instaloader",
    "httpx",
    "httpcore",
    "PIL",
    "urllib3",
    "faster_whisper",
    "filelock",
    "multipart",
    "google.auth",
    "google.api_core",
    "asyncio",
)


class _PipelineFormatter(logging.Formatter):
    """Single-line formatter: ``HH:MM:SS  LEVEL  logger_short  message``."""

    def __init__(self, colours: bool) -> None:
        super().__init__()
        self._colours = colours

    def _c(self, text: str, code: str) -> str:
        return f"{code}{text}{_RESET}" if self._colours else text

    def format(self, record: logging.LogRecord) -> str:
        ts = self.formatTime(record, "%H:%M:%S")
        label, colour = _LEVEL_FMT.get(record.levelno, ("?????", ""))

        # Last dotted segment of the logger name, fixed-width for alignment.
        short = record.name.rsplit(".", 1)[-1][:11].ljust(11)

        msg = record.getMessage()
        if record.exc_info and not record.exc_text:
            record.exc_text = self.formatException(record.exc_info)
        if record.exc_text:
            msg = f"{msg}\n{record.exc_text}"
        if record.stack_info:
            msg = f"{msg}\n{self.formatStack(record.stack_info)}"

        if self._colours:
            return (
                f"{self._c(ts, _DIM)}  "
                f"{self._c(label, colour)}  "
                f"{self._c(short, _CYAN)}  "
                f"{msg}"
            )
        return f"{ts}  {label}  {short}  {msg}"


def configure_logging() -> None:
    """Apply the pipeline formatter and silence third-party noise.

    Designed to be called both at module-import time (before uvicorn applies
    its own config) and again inside the FastAPI lifespan (after uvicorn has
    set up its handlers) so the format is always consistent.
    """
    colours = sys.stderr.isatty()
    fmt = _PipelineFormatter(colours=colours)

    # Root logger: add our handler if absent, or reformat existing ones.
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    if root.handlers:
        for h in root.handlers:
            h.setFormatter(fmt)
            if h.level == logging.NOTSET:
                h.setLevel(logging.INFO)
    else:
        h = logging.StreamHandler(sys.stderr)
        h.setLevel(logging.INFO)
        h.setFormatter(fmt)
        root.addHandler(h)

    # Override uvicorn's handlers so its startup/error messages look consistent.
    for name in ("uvicorn", "uvicorn.error"):
        for h in logging.getLogger(name).handlers:
            h.setFormatter(fmt)

    # Per-request access log is too noisy during development; silence it.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

    # Silence chatty third-party libraries.
    for name in _QUIET_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)
