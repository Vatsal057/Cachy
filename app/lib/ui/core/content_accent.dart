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

  static ContentAccent of(ContentType type) {
    switch (type) {
      case ContentType.recipe:
        return const ContentAccent(Color(0xFFE8643C), Icons.restaurant_rounded);
      case ContentType.workout:
        return const ContentAccent(Color(0xFF2EA86A), Icons.fitness_center_rounded);
      case ContentType.tutorial:
        return const ContentAccent(Color(0xFF4C7DF0), Icons.school_rounded);
      case ContentType.tip:
        return const ContentAccent(Color(0xFFE0A92E), Icons.lightbulb_rounded);
      case ContentType.productList:
        return const ContentAccent(Color(0xFF8E5BD6), Icons.shopping_bag_rounded);
      case ContentType.travel:
        return const ContentAccent(Color(0xFF1FAFB5), Icons.place_rounded);
      case ContentType.newsExplainer:
        return const ContentAccent(Color(0xFF6B7280), Icons.article_rounded);
      case ContentType.other:
        return const ContentAccent(Color(0xFF5B5BD6), Icons.bookmark_rounded);
    }
  }
}
