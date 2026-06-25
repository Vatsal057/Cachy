/// The sealed `Block` type — the renderable vocabulary from docs/04, mirrored
/// from backend models/card.py. One subtype per vocabulary entry. `Block.fromJson`
/// dispatches on `type`; anything outside the vocabulary becomes an [UnknownBlock]
/// so the renderer degrades gracefully and never crashes on a future block type.
library;

sealed class Block {
  const Block({required this.id});

  final String id;

  /// Dispatch on the discriminator `type`. Tolerant: missing/unknown types and
  /// malformed payloads never throw — they fall back to [UnknownBlock].
  factory Block.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final id = (json['id'] as String?) ?? '';
    try {
      switch (type) {
        case 'heading':
          return HeadingBlock(
            id: id,
            text: (json['text'] as String?) ?? '',
            level: (json['level'] as num?)?.toInt() ?? 2,
          );
        case 'paragraph':
          return ParagraphBlock(id: id, text: (json['text'] as String?) ?? '');
        case 'bullet_list':
          return BulletListBlock(
            id: id,
            items: _stringList(json['items']),
          );
        case 'step_list':
          return StepListBlock(
            id: id,
            steps: _list(json['steps'])
                .map((e) => Step.fromJson(_asMap(e)))
                .toList(),
          );
        case 'key_value':
          return KeyValueBlock(
            id: id,
            pairs: _list(json['pairs'])
                .map((e) => KeyValuePair.fromJson(_asMap(e)))
                .toList(),
          );
        case 'checklist':
          return ChecklistBlock(
            id: id,
            items: _list(json['items'])
                .map((e) => ChecklistItem.fromJson(_asMap(e)))
                .toList(),
          );
        case 'callout':
          return CalloutBlock(
            id: id,
            variant: (json['variant'] as String?) ?? 'info',
            text: (json['text'] as String?) ?? '',
            confidence: (json['confidence'] as String?) ?? 'unverified',
            sourceUrl: json['source_url'] as String?,
          );
        case 'link':
          return LinkBlock(
            id: id,
            url: (json['url'] as String?) ?? '',
            label: json['label'] as String?,
          );
        case 'map':
          return MapBlock(
            id: id,
            places: _list(json['places'])
                .map((e) => Place.fromJson(_asMap(e)))
                .toList(),
          );
        case 'table':
          return TableBlock(
            id: id,
            headers: _stringList(json['headers']),
            rows: _list(json['rows']).map(_stringList).toList(),
          );
        default:
          return UnknownBlock(id: id, type: type ?? 'unknown', raw: json);
      }
    } catch (_) {
      // Any shape mismatch degrades to an unknown block rather than crashing.
      return UnknownBlock(id: id, type: type ?? 'unknown', raw: json);
    }
  }
}

class HeadingBlock extends Block {
  const HeadingBlock({required super.id, required this.text, this.level = 2});
  final String text;
  final int level;
}

class ParagraphBlock extends Block {
  const ParagraphBlock({required super.id, required this.text});
  final String text;
}

class BulletListBlock extends Block {
  const BulletListBlock({required super.id, required this.items});
  final List<String> items;
}

class Step {
  const Step({required this.text, this.checkable = true, this.checked = false});
  final String text;
  final bool checkable;
  final bool checked;

  factory Step.fromJson(Map<String, dynamic> json) => Step(
        text: (json['text'] as String?) ?? '',
        checkable: (json['checkable'] as bool?) ?? true,
        checked: (json['checked'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'checkable': checkable,
        'checked': checked,
      };

  Step copyWith({bool? checked}) =>
      Step(text: text, checkable: checkable, checked: checked ?? this.checked);
}

class StepListBlock extends Block {
  const StepListBlock({required super.id, required this.steps});
  final List<Step> steps;
}

class KeyValuePair {
  const KeyValuePair({required this.key, required this.value});
  final String key;
  final String value;

  factory KeyValuePair.fromJson(Map<String, dynamic> json) => KeyValuePair(
        key: (json['key'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

class KeyValueBlock extends Block {
  const KeyValueBlock({required super.id, required this.pairs});
  final List<KeyValuePair> pairs;
}

class ChecklistItem {
  const ChecklistItem({required this.text, this.checked = false});
  final String text;
  final bool checked;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        text: (json['text'] as String?) ?? '',
        checked: (json['checked'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {'text': text, 'checked': checked};

  ChecklistItem copyWith({bool? checked}) =>
      ChecklistItem(text: text, checked: checked ?? this.checked);
}

class ChecklistBlock extends Block {
  const ChecklistBlock({required super.id, required this.items});
  final List<ChecklistItem> items;
}

class CalloutBlock extends Block {
  const CalloutBlock({
    required super.id,
    required this.variant,
    required this.text,
    required this.confidence,
    this.sourceUrl,
  });
  final String variant; // info | warning | caveat | source
  final String text;
  final String confidence; // high | medium | low | unverified
  final String? sourceUrl;
}

class LinkBlock extends Block {
  const LinkBlock({required super.id, required this.url, this.label});
  final String url;
  final String? label;
}

class Place {
  const Place({required this.name, this.lat, this.lng, this.note = ''});
  final String name;
  final double? lat;
  final double? lng;
  final String note;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        name: (json['name'] as String?) ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        note: (json['note'] as String?) ?? '',
      );
}

class MapBlock extends Block {
  const MapBlock({required super.id, required this.places});
  final List<Place> places;
}

class TableBlock extends Block {
  const TableBlock({required super.id, required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;
}

/// Out-of-vocabulary or malformed block. Renders `text`/`items` if present
/// (docs/04 forward-compat rule), else the renderer skips it.
class UnknownBlock extends Block {
  const UnknownBlock({required super.id, required this.type, required this.raw});
  final String type;
  final Map<String, dynamic> raw;

  String? get text => raw['text'] as String?;
  List<String> get items => _stringList(raw['items']);
}

// --------------------------------------------------------------------------- //
// Parsing helpers — all tolerant of nulls/wrong types.
// --------------------------------------------------------------------------- //

List<dynamic> _list(dynamic value) => value is List ? value : const [];

Map<String, dynamic> _asMap(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<String> _stringList(dynamic value) =>
    value is List ? value.map((e) => e?.toString() ?? '').toList() : const [];
