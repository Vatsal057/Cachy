/// Per-content-type accent + icon so a card's kind reads at a glance without an
/// icon zoo (docs/07). Used for state badges, the library face fallback, and the
/// reader's type chip. Restrained: one accent per type, nothing more.
library;

import 'package:flutter/material.dart';

import '../../domain/models/enums.dart';

class ContentAccent {
  const ContentAccent(this.color, this.icon);
  final Color color;
  final IconData icon;

  // Earthy, muted accents that sit inside the cream+ink world — no neon. One
  // accent per type; the rust brand accent stays reserved for chrome.
  static ContentAccent of(ContentType type) {
    switch (type) {
      case ContentType.recipe:
        return const ContentAccent(Color(0xFFB6502E), Icons.restaurant_rounded); // terracotta
      case ContentType.workout:
        return const ContentAccent(Color(0xFF4F6B4A), Icons.fitness_center_rounded); // moss
      case ContentType.tutorial:
        return const ContentAccent(Color(0xFF3E5C73), Icons.school_rounded); // slate blue
      case ContentType.tip:
        return const ContentAccent(Color(0xFFB08227), Icons.lightbulb_rounded); // ochre
      case ContentType.productList:
        return const ContentAccent(Color(0xFF7A5A86), Icons.shopping_bag_rounded); // plum
      case ContentType.travel:
        return const ContentAccent(Color(0xFF2F7E80), Icons.place_rounded); // teal
      case ContentType.newsExplainer:
        return const ContentAccent(Color(0xFF6B6359), Icons.article_rounded); // ink-muted
      case ContentType.other:
        return const ContentAccent(Color(0xFF8A5A3C), Icons.bookmark_rounded); // tan
    }
  }
}
