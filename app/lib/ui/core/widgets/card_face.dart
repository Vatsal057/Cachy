/// A card's "real face" (docs/07): the keyframe/thumbnail. When the image is
/// missing or fails to load (backend media not served yet, offline), it degrades
/// to a calm content-type accent panel — never an empty box, never a crash.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../data/services/api_client.dart';
import '../../../domain/models/card.dart' as model;
import '../content_accent.dart';

class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    required this.api,
    this.fit = BoxFit.cover,
  });

  final model.Card card;
  final ApiClient api;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final thumb = card.thumbnail;
    final accent = ContentAccent.of(card.base.contentType);
    if (thumb == null || thumb.isEmpty) {
      return _AccentFace(accent: accent);
    }
    return CachedNetworkImage(
      imageUrl: api.resolveMedia(thumb),
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => _AccentFace(accent: accent, dim: true),
      errorWidget: (_, _, _) => _AccentFace(accent: accent),
    );
  }
}

class _AccentFace extends StatelessWidget {
  const _AccentFace({required this.accent, this.dim = false});
  final ContentAccent accent;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.color.withValues(alpha: dim ? 0.18 : 0.30),
            accent.color.withValues(alpha: dim ? 0.08 : 0.14),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          accent.icon,
          size: 34,
          color: accent.color.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
