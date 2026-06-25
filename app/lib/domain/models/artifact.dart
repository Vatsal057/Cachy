/// Catalog artifact: a real-world thing a video references — book, movie,
/// podcast, product, place, etc. Mirrors the backend catalog contract
/// (docs/12, backend models/artifact.py). Parsing is tolerant: unknown type
/// degrades to [ArtifactType.other] rather than throwing.
library;

enum ArtifactType {
  book,
  movie,
  tvShow,
  podcast,
  music,
  product,
  place,
  app,
  other;

  static ArtifactType fromWire(String? value) {
    switch (value) {
      case 'book':
        return ArtifactType.book;
      case 'movie':
        return ArtifactType.movie;
      case 'tv_show':
        return ArtifactType.tvShow;
      case 'podcast':
        return ArtifactType.podcast;
      case 'music':
        return ArtifactType.music;
      case 'product':
        return ArtifactType.product;
      case 'place':
        return ArtifactType.place;
      case 'app':
        return ArtifactType.app;
      default:
        return ArtifactType.other;
    }
  }

  String get wire {
    switch (this) {
      case ArtifactType.tvShow:
        return 'tv_show';
      default:
        return name;
    }
  }

  /// Plural label used as a catalog section header.
  String get sectionLabel {
    switch (this) {
      case ArtifactType.book:
        return 'Books';
      case ArtifactType.movie:
        return 'Movies';
      case ArtifactType.tvShow:
        return 'TV Shows';
      case ArtifactType.podcast:
        return 'Podcasts';
      case ArtifactType.music:
        return 'Music';
      case ArtifactType.product:
        return 'Products';
      case ArtifactType.place:
        return 'Places';
      case ArtifactType.app:
        return 'Apps';
      case ArtifactType.other:
        return 'Other';
    }
  }
}

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    this.type = ArtifactType.other,
    required this.title,
    this.creator,
    this.year,
    this.thumbnail,
    this.sourceCardIds = const [],
  });

  final String id;
  final ArtifactType type;
  final String title;
  final String? creator;
  final int? year;
  final String? thumbnail;
  final List<String> sourceCardIds;

  /// "James Clear · 2018", "2018", or "" — the dimmed subtitle line.
  String get subtitle {
    final parts = <String>[
      if (creator != null && creator!.isNotEmpty) creator!,
      if (year != null) '$year',
    ];
    return parts.join(' · ');
  }

  factory CatalogEntry.fromJson(Map<String, dynamic> json) => CatalogEntry(
        id: (json['id'] as String?) ?? '',
        type: ArtifactType.fromWire(json['type'] as String?),
        title: (json['title'] as String?) ?? '',
        creator: json['creator'] as String?,
        year: (json['year'] as num?)?.toInt(),
        thumbnail: json['thumbnail'] as String?,
        sourceCardIds: (json['source_card_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
