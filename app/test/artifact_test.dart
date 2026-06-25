// Contract tests for the catalog artifact mirror (docs/12). Parsing must be
// tolerant: unknown type degrades to `other`, missing fields don't throw.

import 'package:flutter_test/flutter_test.dart';

import 'package:cachy/domain/models/artifact.dart';

void main() {
  group('CatalogEntry.fromJson', () {
    test('parses a full entry', () {
      final e = CatalogEntry.fromJson({
        'id': 'a_1',
        'type': 'book',
        'title': 'Atomic Habits',
        'creator': 'James Clear',
        'year': 2018,
        'thumbnail': 'https://covers/x.jpg',
        'source_card_ids': ['c1', 'c2'],
      });
      expect(e.type, ArtifactType.book);
      expect(e.title, 'Atomic Habits');
      expect(e.subtitle, 'James Clear · 2018');
      expect(e.sourceCardIds, ['c1', 'c2']);
    });

    test('tv_show wire maps to tvShow and back', () {
      expect(ArtifactType.fromWire('tv_show'), ArtifactType.tvShow);
      expect(ArtifactType.tvShow.wire, 'tv_show');
    });

    test('unknown type degrades to other', () {
      final e = CatalogEntry.fromJson({'id': 'a', 'title': 'X', 'type': 'zzz'});
      expect(e.type, ArtifactType.other);
    });

    test('missing optional fields do not throw', () {
      final e = CatalogEntry.fromJson({'id': 'a', 'title': 'Solo'});
      expect(e.creator, isNull);
      expect(e.year, isNull);
      expect(e.thumbnail, isNull);
      expect(e.subtitle, '');
      expect(e.sourceCardIds, isEmpty);
    });
  });
}
