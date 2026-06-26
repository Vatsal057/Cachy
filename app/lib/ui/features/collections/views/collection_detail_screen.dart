library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_tiles.dart';
import '../../library/views/card_tile.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/collections_view_model.dart';

class CollectionDetailScreen extends StatefulWidget {
  const CollectionDetailScreen({super.key, required this.collection});

  final Collection collection;

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  List<model.Card>? _cards;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<CardRepository>();
      final List<model.Card> cards;
      // Use backend collection_id if we have a real UUID; fall back to
      // client-side content_type filtering for the offline/fallback case.
      final id = widget.collection.id;
      final ct = widget.collection.contentType;
      if (id.length > 10) {
        // real UUID from backend
        cards = await repo.listByCollection(id);
      } else if (ct != null) {
        final all = await repo.list();
        cards = all.where((c) => c.base.contentType == ct).toList();
      } else {
        cards = await repo.list();
      }
      if (mounted) setState(() { _cards = cards; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _cards = const []; _loading = false; });
    }
  }

  void _delete(String cardId) {
    setState(() => _cards = _cards?.where((c) => c.cardId != cardId).toList());
    context.read<CardRepository>().delete(cardId).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ct = widget.collection.contentType;
    final accent = ct != null
        ? ContentAccent.of(ct)
        : const ContentAccent(Color(0xFF8A5A3C), PhosphorIconsFill.folder);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: const BackButton(),
        title: Row(
          children: [
            PhosphorIcon(
              widget.collection.isCustom ? PhosphorIconsFill.folder : accent.icon,
              color: accent.color,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              widget.collection.name.toUpperCase(),
              style: Brand.label(
                size: 13,
                color: scheme.onSurface,
                weight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Insets.page),
            child: Text(
              '${widget.collection.count}',
              style: Brand.label(size: 12, color: scheme.onSurfaceVariant, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
      body: _loading
          ? const LoadingTiles()
          : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final cards = _cards ?? const [];
    if (cards.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.folderOpen,
        title: 'Nothing here',
        message: 'Cards you save will appear here once processed.',
      );
    }

    final api = context.read<CardRepository>().api;
    final width = MediaQuery.of(context).size.width;
    final cols = (width / 200).floor().clamp(2, 5);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Insets.page, 8, Insets.page, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        return CardTile(
          card: card,
          api: api,
          onTap: () => Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => ReaderScreen(cardId: card.cardId)),
          ),
          onDelete: () => _delete(card.cardId),
        );
      },
    );
  }
}
