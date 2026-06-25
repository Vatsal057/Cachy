/// Ask-the-card screen (docs/13): a grounded chat over one card's content.
/// Answers come from the backend LLM using only the card as context, so the
/// header carries the standard "AI-generated, may contain errors" note.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../view_models/chat_view_model.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.cardId, required this.title});
  final String cardId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => ChatViewModel(
        repository: ctx.read<CardRepository>(),
        cardId: cardId,
      ),
      child: _ChatView(title: title),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.title});
  final String title;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(ChatViewModel vm) {
    final text = _controller.text;
    _controller.clear();
    vm.send(text).then((_) => _scrollToEnd());
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title.isEmpty ? 'Ask this card' : widget.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              'AI-generated · may contain errors',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _messages(context, vm)),
          if (vm.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(vm.error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          _composer(context, vm),
        ],
      ),
    );
  }

  Widget _messages(BuildContext context, ChatViewModel vm) {
    if (vm.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Ask anything about this card — ingredients, steps, the gist…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: vm.messages.length + (vm.busy ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= vm.messages.length) return const _TypingBubble();
        return _Bubble(message: vm.messages[i]);
      },
    );
  }

  Widget _composer(BuildContext context, ChatViewModel vm) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(vm),
                decoration: const InputDecoration(
                  hintText: 'Ask about this card',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: vm.busy ? null : () => _send(vm),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
