library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../data/services/api_client.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../view_models/collections_view_model.dart';
import '../../../core/widgets/card_face.dart';

class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.collection,
    required this.api,
    required this.onTap,
    this.onLongPress,
  });

  final Collection collection;
  final ApiClient api;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ct = collection.contentType;
    final accent = ct != null
        ? ContentAccent.of(ct)
        : const ContentAccent(Color(0xFF8A5A3C), PhosphorIconsFill.folder);
    final preview = collection.previewCard;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preview != null)
              Opacity(opacity: 0.55, child: CardFace(card: preview, api: api))
            else
              ColoredBox(color: accent.color.withValues(alpha: 0.18)),

            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.color.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),

            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent.color.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: PhosphorIcon(
                  collection.isCustom ? PhosphorIconsFill.folder : accent.icon,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),

            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.40),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${collection.count}',
                  style: Brand.label(size: 10, color: Colors.white, weight: FontWeight.w700),
                ),
              ),
            ),

            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                collection.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Brand.label(
                  size: 11,
                  color: Colors.white,
                  weight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
