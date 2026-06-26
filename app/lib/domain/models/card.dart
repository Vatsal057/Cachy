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
  final String? platform; // instagram | youtube
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
    this.tags = const [],
  });

  final String oneLiner;
  final String tldr;
  final ContentType contentType;
  final double typeConfidence;
  final List<String> tags; // auto-tags for browse/filter (docs/09, schema 1.2)

  factory Base.fromJson(Map<String, dynamic> json) => Base(
        oneLiner: (json['one_liner'] as String?) ?? '',
        tldr: (json['tldr'] as String?) ?? '',
        contentType: ContentType.fromWire(json['content_type'] as String?),
        typeConfidence: (json['type_confidence'] as num?)?.toDouble() ?? 0.0,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
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

/// One concrete to-do the reel tells the viewer to do (docs/13).
class ActionItem {
  const ActionItem({required this.id, required this.text, this.done = false});

  final String id;
  final String text;
  final bool done;

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
        id: (json['id'] as String?) ?? '',
        text: (json['text'] as String?) ?? '',
        done: (json['done'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
}

/// Per-card action list (docs/13). `followed` flips true when the user opts the
/// card into the Actions hub; until then the list is inert.
class ActionItems {
  const ActionItems({this.followed = false, this.items = const []});

  final bool followed;
  final List<ActionItem> items;

  bool get isPresent => items.isNotEmpty;

  factory ActionItems.fromJson(Map<String, dynamic> json) => ActionItems(
        followed: (json['followed'] as bool?) ?? false,
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ActionItem.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'followed': followed, 'items': items.map((e) => e.toJson()).toList()};
}

/// Deep-analysis layer (docs/14). Present only on idea-rich cards; `null` for a
/// simple reel. Everything here is actionable: rabbit-hole threads tap into chat,
/// the topic map orients, the research prompt is paste-ready. Each sub-section is
/// independently optional — the UI renders only the parts that carry content.
class Insight {
  const Insight({
    this.rabbitHole = const RabbitHole(),
    this.topicMap,
    this.deepResearchPrompt,
  });

  final RabbitHole rabbitHole;
  final TopicMap? topicMap;
  final String? deepResearchPrompt;

  bool get hasDeepResearch =>
      deepResearchPrompt != null && deepResearchPrompt!.trim().isNotEmpty;
  bool get hasContent => !rabbitHole.isEmpty || topicMap != null || hasDeepResearch;

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
        rabbitHole: RabbitHole.fromJson(
          (json['rabbit_hole'] as Map<String, dynamic>?) ?? const {},
        ),
        topicMap: json['topic_map'] is Map<String, dynamic>
            ? TopicMap.fromJson(json['topic_map'] as Map<String, dynamic>)
            : null,
        deepResearchPrompt: json['deep_research_prompt'] as String?,
      );
}

class RabbitHole {
  const RabbitHole({
    this.questions = const [],
    this.adjacentTopics = const [],
    this.advancedConcepts = const [],
  });

  final List<String> questions;
  final List<String> adjacentTopics;
  final List<String> advancedConcepts;

  bool get isEmpty =>
      questions.isEmpty && adjacentTopics.isEmpty && advancedConcepts.isEmpty;

  factory RabbitHole.fromJson(Map<String, dynamic> json) {
    List<String> l(String k) =>
        ((json[k] as List?) ?? const []).map((e) => e.toString()).toList();
    return RabbitHole(
      questions: l('questions'),
      adjacentTopics: l('adjacent_topics'),
      advancedConcepts: l('advanced_concepts'),
    );
  }
}

class TopicMap {
  const TopicMap({required this.center, this.nodes = const []});

  final String center;
  final List<String> nodes;

  factory TopicMap.fromJson(Map<String, dynamic> json) => TopicMap(
        center: (json['center'] as String?) ?? '',
        nodes: ((json['nodes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
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
    this.actionItems = const ActionItems(),
    this.blocks = const [],
    this.insight,
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
  final ActionItems actionItems;
  final List<Block> blocks;
  final Insight? insight; // deep-analysis layer (docs/14); null for simple cards
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
      actionItems: ActionItems.fromJson(
        (json['action_items'] as Map<String, dynamic>?) ?? const {},
      ),
      blocks: rawBlocks.map(Block.fromJson).toList(),
      insight: json['insight'] is Map<String, dynamic>
          ? Insight.fromJson(json['insight'] as Map<String, dynamic>)
          : null,
      media: Media.fromJson((json['media'] as Map<String, dynamic>?) ?? const {}),
      meta: Meta.fromJson((json['meta'] as Map<String, dynamic>?) ?? const {}),
      rawBlocks: rawBlocks,
    );
  }

  Card copyWith({
    CardState? state,
    ActionItems? actionItems,
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
        actionItems: actionItems ?? this.actionItems,
        blocks: blocks ?? this.blocks,
        insight: insight,
        media: media,
        meta: meta,
        rawBlocks: rawBlocks ?? this.rawBlocks,
      );
}
