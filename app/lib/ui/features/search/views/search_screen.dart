/// Full-text search over the library (docs/06), backed by the existing
/// `/search` endpoint via [CardRepository.search]. Debounced query, result wall
/// reusing [CardTile], and designed empty / no-results / error states.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../library/views/card_tile.dart';
import '../../reader/views/reader_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Status { idle, loading, results, empty, error }

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  _Status _status = _Status.idle;
  List<model.Card> _results = const [];
  String _query = '';

  void _onChanged(String value) {
    _query = value.trim();
    _debounce?.cancel();
    if (_query.isEmpty) {
      setState(() => _status = _Status.idle);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), _run);
  }

  Future<void> _run() async {
    final repo = context.read<CardRepository>();
    setState(() => _status = _Status.loading);
    try {
      final cards = await repo.search(_query);
      if (!mounted) return;
      setState(() {
        _results = cards;
        _status = cards.isEmpty ? _Status.empty : _Status.results;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _Status.error);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search your cards…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    switch (_status) {
      case _Status.idle:
        return const EmptyState(
          icon: Icons.search_rounded,
          title: 'Search everything',
          message: 'Find a recipe step, a place, a product — across every card you\'ve saved.',
        );
      case _Status.loading:
        return const Center(child: CircularProgressIndicator());
      case _Status.error:
        return ErrorState(
          message: 'Couldn\'t reach search. Check your connection and try again.',
          onRetry: _run,
        );
      case _Status.empty:
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          message: 'Nothing matched "$_query". Try a different word.',
        );
      case _Status.results:
        final api = context.read<CardRepository>().api;
        final cols = (MediaQuery.of(context).size.width / 200).floor().clamp(2, 5);
        return GridView.builder(
          padding: const EdgeInsets.all(Insets.page),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: Insets.block,
            crossAxisSpacing: Insets.block,
            childAspectRatio: 0.72,
          ),
          itemCount: _results.length,
          itemBuilder: (_, i) {
            final card = _results[i];
            return CardTile(
              card: card,
              api: api,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(cardId: card.cardId),
                ),
              ),
              onDelete: () {},
            );
          },
        );
    }
  }
}
