/// Per-content-type accent + icon so a card's kind reads at a glance without an
/// icon zoo (docs/07). Used for state badges, the library face fallback, and the
/// reader's type chip. Restrained: one accent per type, nothing more.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models/enums.dart';

class ContentAccent {
  const ContentAccent(this.color, this.icon);
  final Color color;
  final PhosphorIconData icon;

  static ContentAccent of(ContentType type) {
    switch (type) {
      case ContentType.recipe:
        return const ContentAccent(Color(0xFFB6502E), PhosphorIconsRegular.cookingPot);
      case ContentType.workout:
        return const ContentAccent(Color(0xFF4F6B4A), PhosphorIconsRegular.barbell);
      case ContentType.tutorial:
        return const ContentAccent(Color(0xFF3E5C73), PhosphorIconsRegular.graduationCap);
      case ContentType.tip:
        return const ContentAccent(Color(0xFFB08227), PhosphorIconsRegular.lightbulb);
      case ContentType.productList:
        return const ContentAccent(Color(0xFF7A5A86), PhosphorIconsRegular.shoppingBag);
      case ContentType.travel:
        return const ContentAccent(Color(0xFF2F7E80), PhosphorIconsRegular.mapPin);
      case ContentType.newsExplainer:
        return const ContentAccent(Color(0xFF6B6359), PhosphorIconsRegular.article);
      case ContentType.other:
        return const ContentAccent(Color(0xFF8A5A3C), PhosphorIconsFill.bookmark);
    }
  }
}
