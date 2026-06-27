library;

class Highlight {
  const Highlight({
    required this.id,
    required this.cardId,
    required this.cardTitle,
    required this.text,
    required this.colorIndex,
    required this.createdAt,
  });

  final String id;
  final String cardId;
  final String cardTitle;
  final String text;
  final int colorIndex;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'card_id': cardId,
        'card_title': cardTitle,
        'text': text,
        'color_index': colorIndex,
        'created_at': createdAt.toIso8601String(),
      };

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
        id: json['id'] as String,
        cardId: json['card_id'] as String,
        cardTitle: (json['card_title'] as String?) ?? '',
        text: json['text'] as String,
        colorIndex: (json['color_index'] as int?) ?? 0,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
