/// Models for the Knowledge Feed and the Connections (serendipity) view — a
/// reel-style stream of "moments" built from the user's own cards, plus the
/// surprising links the backend finds between pairs of cards. Mirrors the
/// backend schemas in api/feed.py and api/connections.py.
library;

import 'enums.dart';

/// A lightweight pointer to a source card, enough to render a moment header and
/// deep-link into the reader.
class FeedCardRef {
  const FeedCardRef({
    required this.cardId,
    required this.title,
    required this.contentType,
    this.thumbnail,
  });

  final String cardId;
  final String title;
  final ContentType contentType;
  final String? thumbnail;

  factory FeedCardRef.fromJson(Map<String, dynamic> json) => FeedCardRef(
        cardId: (json['card_id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        contentType: ContentType.fromWire(json['content_type'] as String?),
        thumbnail: json['thumbnail'] as String?,
      );
}

enum FeedItemKind {
  insight,
  highlight,
  quiz,
  thread,
  connection,
  unknown;

  static FeedItemKind fromWire(String? value) {
    switch (value) {
      case 'insight':
        return FeedItemKind.insight;
      case 'highlight':
        return FeedItemKind.highlight;
      case 'quiz':
        return FeedItemKind.quiz;
      case 'thread':
        return FeedItemKind.thread;
      case 'connection':
        return FeedItemKind.connection;
      default:
        return FeedItemKind.unknown;
    }
  }
}

/// One swipeable moment in the feed. Fields are kind-specific; unused ones stay
/// at their defaults.
class FeedItem {
  const FeedItem({
    required this.id,
    required this.kind,
    required this.card,
    this.text = '',
    this.question = '',
    this.options = const [],
    this.answerIndex = 0,
    this.explanation = '',
    this.cardB,
  });

  final String id;
  final FeedItemKind kind;
  final FeedCardRef card;

  /// insight TL;DR / highlight line / thread prompt / connection blurb.
  final String text;

  // quiz-specific
  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;

  /// connection-specific — the second card in the pair.
  final FeedCardRef? cardB;

  bool get quizValid =>
      question.trim().isNotEmpty &&
      options.length >= 2 &&
      answerIndex >= 0 &&
      answerIndex < options.length;

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        id: (json['id'] as String?) ?? '',
        kind: FeedItemKind.fromWire(json['kind'] as String?),
        card: FeedCardRef.fromJson(
          (json['card'] as Map<String, dynamic>?) ?? const {},
        ),
        text: (json['text'] as String?) ?? '',
        question: (json['question'] as String?) ?? '',
        options: ((json['options'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        answerIndex: (json['answer_index'] as num?)?.toInt() ?? 0,
        explanation: (json['explanation'] as String?) ?? '',
        cardB: json['card_b'] is Map<String, dynamic>
            ? FeedCardRef.fromJson(json['card_b'] as Map<String, dynamic>)
            : null,
      );
}

/// A surprising link between two of the user's cards (the serendipity engine).
class Connection {
  const Connection({
    required this.cardA,
    required this.cardB,
    required this.blurb,
  });

  final FeedCardRef cardA;
  final FeedCardRef cardB;
  final String blurb;

  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
        cardA: FeedCardRef.fromJson(
          (json['card_a'] as Map<String, dynamic>?) ?? const {},
        ),
        cardB: FeedCardRef.fromJson(
          (json['card_b'] as Map<String, dynamic>?) ?? const {},
        ),
        blurb: (json['blurb'] as String?) ?? '',
      );
}
