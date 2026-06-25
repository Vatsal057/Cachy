/// Ask-your-library screen (docs/09): grounded chat across every saved card.
/// Answers are synthesised from the cards most relevant to the question; the
/// header carries the standard "AI-generated, may contain errors" note, and the
/// cards used are shown as tappable source chips.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/library_chat_view_model.dart';

class LibraryChatScreen extends StatelessWidget {
  const LibraryChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          LibraryChatViewModel(repository: ctx.read<CardRepository>()),
      child: const _LibraryChatView(),
    );
  }
}

class _LibraryChatView extends StatefulWidget {
  const _LibraryChatView();

  @override
  State<_LibraryChatView> createState() => _LibraryChatViewState();
}

class _LibraryChatViewState extends State<_LibraryChatView> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(LibraryChatViewModel vm) {
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
    final vm = context.watch<LibraryChatViewModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask your library'),
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
          if (vm.sources.isNotEmpty && !vm.busy) _sources(context, vm),
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

  Widget _messages(BuildContext context, LibraryChatViewModel vm) {
    if (vm.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Ask anything across your saved cards — "what workouts have I saved?", '
            '"summarise the budgeting tips"…',
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

  Widget _sources(BuildContext context, LibraryChatViewModel vm) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sources',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in vm.sources)
                  ActionChip(
                    avatar: const Icon(Icons.article_outlined, size: 16),
                    label: Text(
                      s.oneLiner.isEmpty ? 'Card' : s.oneLiner,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReaderScreen(cardId: s.cardId),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context, LibraryChatViewModel vm) {
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
                  hintText: 'Ask your library',
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
  final LibraryChatMessage message;

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
          color:
              isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
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
