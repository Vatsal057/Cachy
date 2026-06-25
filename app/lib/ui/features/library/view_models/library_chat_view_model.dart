/// Chat across the whole library (docs/09): cross-card grounded Q&A. Stateless
/// on the server — this view model holds the conversation and replays the full
/// history each turn, mirroring the single-card [ChatViewModel].
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';

class LibraryChatMessage {
  const LibraryChatMessage({required this.role, required this.content});
  final String role; // "user" | "assistant"
  final String content;

  bool get isUser => role == 'user';
  Map<String, String> toWire() => {'role': role, 'content': content};
}

class LibraryChatViewModel extends ChangeNotifier {
  LibraryChatViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  final List<LibraryChatMessage> _messages = [];
  List<LibraryChatMessage> get messages => List.unmodifiable(_messages);

  /// Cards the most recent answer was grounded on (shown as tappable chips).
  List<LibrarySource> _sources = const [];
  List<LibrarySource> get sources => List.unmodifiable(_sources);

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  bool get isEmpty => _messages.isEmpty;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;

    _messages.add(LibraryChatMessage(role: 'user', content: trimmed));
    _busy = true;
    _error = null;
    _sources = const [];
    notifyListeners();

    try {
      final result = await _repository.libraryChat(
        _messages.map((m) => m.toWire()).toList(),
      );
      _messages
          .add(LibraryChatMessage(role: 'assistant', content: result.reply));
      _sources = result.sources;
    } on ApiException catch (e) {
      _error = e.statusCode == 503
          ? 'Chat is unavailable — no AI backend is configured.'
          : "Couldn't get an answer. Try again.";
    } catch (_) {
      _error = "Couldn't reach the backend.";
    }
    _busy = false;
    notifyListeners();
  }
}
