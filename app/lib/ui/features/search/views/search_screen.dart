/// Full-text search over the library (docs/06), backed by the existing
/// `/search` endpoint via [CardRepository.search]. Debounced query, result wall
/// reusing [CardTile], and designed empty / no-results / error states.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/enums.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../capture/views/capture_sheet.dart';
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
  ContentType? _filter; // null = All

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
        _filter = null; // reset filter on a fresh query
        _status = cards.isEmpty ? _Status.empty : _Status.results;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _Status.error);
    }
  }

  /// Content types actually present in the current results — only offer filters
  /// that match something, in the order they appear.
  List<ContentType> get _presentTypes {
    final seen = <ContentType>[];
    for (final c in _results) {
      if (!seen.contains(c.base.contentType)) seen.add(c.base.contentType);
    }
    return seen;
  }

  List<model.Card> get _filtered => _filter == null
      ? _results
      : _results.where((c) => c.base.contentType == _filter).toList();

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
          message: 'Nothing matched "$_query". Try a different word, or capture a reel about it.',
          actionLabel: 'Capture a reel',
          onAction: () => showCaptureSheet(context),
        );
      case _Status.results:
        final api = context.read<CardRepository>().api;
        final cols = (MediaQuery.of(context).size.width / 200).floor().clamp(2, 5);
        final cards = _filtered;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterBar(
              types: _presentTypes,
              selected: _filter,
              total: _results.length,
              shown: cards.length,
              onSelect: (t) => setState(() => _filter = t),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                    Insets.page, 4, Insets.page, Insets.page),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: Insets.block,
                  crossAxisSpacing: Insets.block,
                  childAspectRatio: 0.72,
                ),
                itemCount: cards.length,
                itemBuilder: (_, i) {
                  final card = cards[i];
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
              ),
            ),
          ],
        );
    }
  }
}

/// Result count + content-type filter pills above the result wall. Only shows
/// filters for types present in the results (docs/06 search).
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.types,
    required this.selected,
    required this.total,
    required this.shown,
    required this.onSelect,
  });

  final List<ContentType> types;
  final ContentType? selected;
  final int total;
  final int shown;
  final ValueChanged<ContentType?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = selected == null ? total : shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, 10, Insets.page, 8),
          child: Text(
            '$count ${count == 1 ? 'result' : 'results'}',
            style: Brand.label(
                size: 11, color: scheme.onSurfaceVariant, weight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Insets.page),
            children: [
              _Chip(
                label: 'All',
                selected: selected == null,
                onTap: () => onSelect(null),
              ),
              for (final t in types)
                _Chip(
                  label: t.label,
                  selected: selected == t,
                  onTap: () => onSelect(t),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant),
          ),
          child: Text(
            label,
            style: Brand.label(
              size: 11,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              weight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
