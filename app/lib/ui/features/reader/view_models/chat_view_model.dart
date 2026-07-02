/// Chat Q&A over a single card (docs/13). Stateless on the server: this view
/// model holds the conversation and replays the whole history on every turn.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../core/safe_notifier.dart';

class ChatMessage {
  const ChatMessage({required this.role, required this.content});
  final String role; // "user" | "assistant"
  final String content;

  bool get isUser => role == 'user';
  Map<String, String> toWire() => {'role': role, 'content': content};
}

class ChatViewModel extends ChangeNotifier with SafeNotifier {
  ChatViewModel({required CardRepository repository, required this.cardId})
      : _repository = repository;

  final CardRepository _repository;
  final String cardId;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _busy = false;
  bool get busy => _busy;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  bool get isEmpty => _messages.isEmpty;

  /// Load the saved conversation on entry, then fire an opening question only if
  /// there's nothing to restore (rabbit-hole/ask tap → grounded chat). Prior
  /// turns are owner-scoped and preserved server-side (docs/14).
  void bootstrap({String? seed}) {
    Future.microtask(() async {
      _loading = true;
      notifyListeners();
      try {
        final saved = await _repository.chatHistory(cardId);
        _messages.addAll(saved.map(
          (m) => ChatMessage(role: m['role'] ?? '', content: m['content'] ?? ''),
        ));
      } catch (_) {
        // Best-effort restore; a fresh conversation is fine.
      }
      _loading = false;
      notifyListeners();
      if (_messages.isEmpty && seed != null && seed.trim().isNotEmpty) {
        send(seed);
      }
    });
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;

    _messages.add(ChatMessage(role: 'user', content: trimmed));
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final reply = await _repository.chat(
        cardId,
        _messages.map((m) => m.toWire()).toList(),
      );
      _messages.add(ChatMessage(role: 'assistant', content: reply));
    } on ApiException catch (e) {
      _error = e.statusCode == 503
          ? 'The AI is catching its breath — try again in a moment.'
          : "Couldn't get an answer. Try again.";
    } catch (_) {
      _error = "Couldn't reach the backend.";
    }
    _busy = false;
    notifyListeners();
  }
}
