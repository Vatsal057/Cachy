/// `Card` and its parts, mirroring the backend schema contract (docs/04,
/// backend models/card.py). Parsing is tolerant so a partially-persisted card
/// (progressive render) still constructs cleanly.
library;

import 'block.dart';
import 'enums.dart';

class Source {
  const Source({
    required this.url,
    this.platform,
    this.creator,
    this.caption = '',
    this.durationSeconds,
    this.resolver,
  });

  final String url;
  final String? platform; // instagram | tiktok | youtube
  final String? creator;
  final String caption;
  final int? durationSeconds;
  final String? resolver;

  factory Source.fromJson(Map<String, dynamic> json) => Source(
        url: (json['url'] as String?) ?? '',
        platform: json['platform'] as String?,
        creator: json['creator'] as String?,
        caption: (json['caption'] as String?) ?? '',
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        resolver: json['resolver'] as String?,
      );
}

class Base {
  const Base({
    this.oneLiner = '',
    this.tldr = '',
    this.contentType = ContentType.other,
    this.typeConfidence = 0.0,
  });

  final String oneLiner;
  final String tldr;
  final ContentType contentType;
  final double typeConfidence;

  factory Base.fromJson(Map<String, dynamic> json) => Base(
        oneLiner: (json['one_liner'] as String?) ?? '',
        tldr: (json['tldr'] as String?) ?? '',
        contentType: ContentType.fromWire(json['content_type'] as String?),
        typeConfidence: (json['type_confidence'] as num?)?.toDouble() ?? 0.0,
      );
}

class PrimaryAction {
  const PrimaryAction({
    this.kind = PrimaryActionKind.none,
    this.label = '',
    this.payload = const {},
  });

  final PrimaryActionKind kind;
  final String label;
  final Map<String, dynamic> payload;

  bool get isPresent => kind != PrimaryActionKind.none && label.isNotEmpty;

  factory PrimaryAction.fromJson(Map<String, dynamic> json) => PrimaryAction(
        kind: PrimaryActionKind.fromWire(json['kind'] as String?),
        label: (json['label'] as String?) ?? '',
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      );
}

class Media {
  const Media({this.thumbnail, this.keyframes = const []});

  final String? thumbnail;
  final List<String> keyframes;

  factory Media.fromJson(Map<String, dynamic> json) => Media(
        thumbnail: json['thumbnail'] as String?,
        keyframes: (json['keyframes'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

class ExtractionFlags {
  const ExtractionFlags({
    this.transcript = false,
    this.ocr = false,
    this.visual = false,
  });

  final bool transcript;
  final bool ocr;
  final bool visual;

  factory ExtractionFlags.fromJson(Map<String, dynamic> json) => ExtractionFlags(
        transcript: (json['transcript'] as bool?) ?? false,
        ocr: (json['ocr'] as bool?) ?? false,
        visual: (json['visual'] as bool?) ?? false,
      );
}

class Meta {
  const Meta({this.createdAt, this.extraction = const ExtractionFlags()});

  final DateTime? createdAt;
  final ExtractionFlags extraction;

  factory Meta.fromJson(Map<String, dynamic> json) => Meta(
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
        extraction: ExtractionFlags.fromJson(
          (json['extraction'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

class Card {
  const Card({
    required this.cardId,
    this.schemaVersion = '1.0',
    this.state = CardState.queued,
    this.failureReason,
    required this.source,
    this.base = const Base(),
    this.primaryAction = const PrimaryAction(),
    this.blocks = const [],
    this.media = const Media(),
    this.meta = const Meta(),
    this.rawBlocks = const [],
  });

  final String schemaVersion;
  final String cardId;
  final CardState state;
  final FailureReason? failureReason;
  final Source source;
  final Base base;
  final PrimaryAction primaryAction;
  final List<Block> blocks;
  final Media media;
  final Meta meta;

  /// The original block JSON, preserved so PATCH (checked-item persistence) can
  /// round-trip unmodified fields without lossy re-serialization of the union.
  final List<Map<String, dynamic>> rawBlocks;

  bool get isReady => state == CardState.ready;
  bool get isFailed => state == CardState.failed;
  bool get isProcessing =>
      state == CardState.queued || state == CardState.processing;

  String? get thumbnail => media.thumbnail ??
      (media.keyframes.isNotEmpty ? media.keyframes.first : null);

  factory Card.fromJson(Map<String, dynamic> json) {
    final rawBlocks = ((json['blocks'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Card(
      schemaVersion: (json['schema_version'] as String?) ?? '1.0',
      cardId: (json['card_id'] as String?) ?? '',
      state: CardState.fromWire(json['state'] as String?),
      failureReason: FailureReason.fromWire(json['failure_reason'] as String?),
      source: Source.fromJson(
        (json['source'] as Map<String, dynamic>?) ?? const {},
      ),
      base: Base.fromJson((json['base'] as Map<String, dynamic>?) ?? const {}),
      primaryAction: PrimaryAction.fromJson(
        (json['primary_action'] as Map<String, dynamic>?) ?? const {},
      ),
      blocks: rawBlocks.map(Block.fromJson).toList(),
      media: Media.fromJson((json['media'] as Map<String, dynamic>?) ?? const {}),
      meta: Meta.fromJson((json['meta'] as Map<String, dynamic>?) ?? const {}),
      rawBlocks: rawBlocks,
    );
  }

  Card copyWith({
    CardState? state,
    List<Block>? blocks,
    List<Map<String, dynamic>>? rawBlocks,
  }) =>
      Card(
        schemaVersion: schemaVersion,
        cardId: cardId,
        state: state ?? this.state,
        failureReason: failureReason,
        source: source,
        base: base,
        primaryAction: primaryAction,
        blocks: blocks ?? this.blocks,
        media: media,
        meta: meta,
        rawBlocks: rawBlocks ?? this.rawBlocks,
      );
}
