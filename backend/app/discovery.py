"""Temporary LAN auto-connect for local testing (NOT for production).

The phone app UDP-broadcasts a probe on the local WiFi; this responder replies
with the backend's HTTP port. The app reads the backend IP from the reply's
source address and builds `http://<ip>:<port>` — zero config, no typing an IP.

Harmless once deployed (e.g. Hugging Face): a phone on a different network never
reaches this socket, and the app skips discovery entirely when CACHY_API_BASE is
set to a real URL. Disable here with CACHY_LAN_DISCOVERY=0.
"""

from __future__ import annotations

import asyncio
import logging
import os

log = logging.getLogger("discovery")

_DISCOVERY_PORT = 50505
_PROBE = b"CACHY_DISCOVER?"


class _DiscoveryProtocol(asyncio.DatagramProtocol):
    def __init__(self, http_port: int) -> None:
        self._http_port = http_port
        self._transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self._transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, addr) -> None:
        if data.strip() != _PROBE or self._transport is None:
            return
        self._transport.sendto(f"CACHY|{self._http_port}".encode(), addr)
        log.info("LAN discovery: replied to %s with port %d", addr[0], self._http_port)


async def start_discovery() -> asyncio.DatagramTransport | None:
    """Bind the UDP responder. Returns the transport (close it on shutdown), or
    None if disabled or binding failed — discovery is best-effort, never fatal."""
    if os.environ.get("CACHY_LAN_DISCOVERY", "1") == "0":
        return None
    http_port = int(os.environ.get("CACHY_HTTP_PORT", "8000"))
    try:
        loop = asyncio.get_running_loop()
        transport, _ = await loop.create_datagram_endpoint(
            lambda: _DiscoveryProtocol(http_port),
            local_addr=("0.0.0.0", _DISCOVERY_PORT),
            allow_broadcast=True,
        )
        log.info("LAN discovery responder listening on udp/%d", _DISCOVERY_PORT)
        return transport  # type: ignore[return-value]
    except Exception as e:  # noqa: BLE001 — discovery must never block startup
        log.warning("LAN discovery unavailable: %s", e)
        return None
