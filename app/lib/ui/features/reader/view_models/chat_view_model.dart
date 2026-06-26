/// Chat Q&A over a single card (docs/13). Stateless on the server: this view
/// model holds the conversation and replays the whole history on every turn.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';

class ChatMessage {
  const ChatMessage({required this.role, required this.content});
  final String role; // "user" | "assistant"
  final String content;

  bool get isUser => role == 'user';
  Map<String, String> toWire() => {'role': role, 'content': content};
}

class ChatViewModel extends ChangeNotifier {
  ChatViewModel({required CardRepository repository, required this.cardId})
      : _repository = repository;

  final CardRepository _repository;
  final String cardId;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  bool get isEmpty => _messages.isEmpty;

  /// Fire an opening question on entry (rabbit-hole tap → grounded chat). Runs
  /// after the first frame so the screen is already mounted when the reply lands.
  void seed(String? text) {
    if (text == null || text.trim().isEmpty) return;
    Future.microtask(() => send(text));
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
          ? 'Chat is unavailable — no AI backend is configured.'
          : "Couldn't get an answer. Try again.";
    } catch (_) {
      _error = "Couldn't reach the backend.";
    }
    _busy = false;
    notifyListeners();
  }
}
