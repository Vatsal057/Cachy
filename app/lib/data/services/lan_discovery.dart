/// Temporary LAN auto-connect for local testing (NOT for production).
///
/// Broadcasts a UDP probe on the local WiFi and waits for a backend running
/// `app/discovery.py` to reply with its HTTP port. The base URL is built from
/// the reply's source IP, so the phone finds the dev machine with zero config.
///
/// Returns null on timeout; the caller falls back to the build-time default.
/// Skipped entirely once CACHY_API_BASE points at a real (e.g. Hugging Face)
/// deploy — see [ApiClient.resolveBaseUrl].
library;

import 'dart:async';
import 'dart:io';

const _discoveryPort = 50505;
const _probe = 'CACHY_DISCOVER?';

/// Discover a backend on the same network. `http://<ip>:<port>` or null.
Future<String?> discoverBackend({
  Duration timeout = const Duration(seconds: 2),
}) async {
  RawDatagramSocket? socket;
  Timer? retry;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final completer = Completer<String?>();

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket!.receive();
      if (dg == null) return;
      final msg = String.fromCharCodes(dg.data).trim();
      if (!msg.startsWith('CACHY|')) return;
      final port = int.tryParse(msg.substring(6).trim());
      if (port != null && !completer.isCompleted) {
        completer.complete('http://${dg.address.address}:$port');
      }
    });

    void sendProbe() => socket!
        .send(_probe.codeUnits, InternetAddress('255.255.255.255'), _discoveryPort);

    sendProbe();
    // Re-probe in case the first datagram is dropped (UDP is lossy).
    retry = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!completer.isCompleted) sendProbe();
    });

    return await completer.future.timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null; // discovery is best-effort — never block app launch
  } finally {
    retry?.cancel();
    socket?.close();
  }
}
