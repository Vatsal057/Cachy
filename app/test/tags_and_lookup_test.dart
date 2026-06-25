// Unit tests for Base.tags JSON parsing (schema 1.2) and lookupUri routing
// (docs/09). No network calls; url_launcher is not exercised.

import 'package:flutter_test/flutter_test.dart';

import 'package:cachy/domain/models/artifact.dart';
import 'package:cachy/domain/models/card.dart';
import 'package:cachy/ui/features/catalog/services/artifact_lookup.dart';

void main() {
  group('Base.tags parsing', () {
    test('parses a list of strings', () {
      final base = Base.fromJson({'tags': ['aws', 'cloud', 'cost']});
      expect(base.tags, ['aws', 'cloud', 'cost']);
    });

    test('absent tags defaults to empty list', () {
      final base = Base.fromJson({'one_liner': 'x'});
      expect(base.tags, isEmpty);
    });

    test('null tags field defaults to empty list', () {
      final base = Base.fromJson({'tags': null});
      expect(base.tags, isEmpty);
    });

    test('non-string entries are coerced via toString', () {
      final base = Base.fromJson({'tags': ['good', 42, true]});
      // The Dart side uses .toString() to be tolerant (matching _coerce_tags).
      expect(base.tags, hasLength(3));
      expect(base.tags[0], 'good');
    });

    test('Card.fromJson propagates tags through base', () {
      final card = Card.fromJson({
        'card_id': 'test-1',
        'state': 'ready',
        'base': {
          'one_liner': 'Save money on AWS',
          'tldr': 'Three tips.',
          'tags': ['aws', 'savings'],
        },
        'blocks': [],
      });
      expect(card.base.tags, ['aws', 'savings']);
    });

    test('Card.fromJson with no tags gives empty list', () {
      final card = Card.fromJson({
        'card_id': 'test-2',
        'state': 'queued',
        'blocks': [],
      });
      expect(card.base.tags, isEmpty);
    });
  });

  group('lookupUri', () {
    CatalogEntry makeEntry(ArtifactType type, String title, {String? creator}) =>
        CatalogEntry(
          id: 'a1',
          type: type,
          title: title,
          creator: creator,
          year: null,
          thumbnail: null,
          sourceCardIds: const [],
        );

    test('product → Google Shopping', () {
      final uri = lookupUri(makeEntry(ArtifactType.product, 'Ninja Air Fryer'));
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters['tbm'], 'shop');
    });

    test('book → Google Books', () {
      final uri = lookupUri(makeEntry(ArtifactType.book, 'Atomic Habits', creator: 'James Clear'));
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters['tbm'], 'bks');
      expect(uri.queryParameters['q'], contains('Atomic Habits'));
    });

    test('movie → IMDb', () {
      final uri = lookupUri(makeEntry(ArtifactType.movie, 'Inception'));
      expect(uri.host, 'www.imdb.com');
    });

    test('tvShow → IMDb', () {
      final uri = lookupUri(makeEntry(ArtifactType.tvShow, 'Breaking Bad'));
      expect(uri.host, 'www.imdb.com');
    });

    test('podcast → Apple Music', () {
      final uri = lookupUri(makeEntry(ArtifactType.podcast, 'Lex Fridman'));
      expect(uri.host, 'music.apple.com');
    });

    test('music → Apple Music', () {
      final uri = lookupUri(makeEntry(ArtifactType.music, 'Blinding Lights'));
      expect(uri.host, 'music.apple.com');
    });

    test('app → Google Search', () {
      final uri = lookupUri(makeEntry(ArtifactType.app, 'Notion'));
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters['q'], 'Notion');
    });

    test('place → Google Maps', () {
      final uri = lookupUri(makeEntry(ArtifactType.place, 'Eiffel Tower'));
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
    });

    test('other → Google Search', () {
      final uri = lookupUri(makeEntry(ArtifactType.other, 'some thing'));
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters.containsKey('tbm'), isFalse);
    });

    test('creator included in query when present', () {
      final uri = lookupUri(makeEntry(ArtifactType.book, 'Dune', creator: 'Frank Herbert'));
      final q = uri.queryParameters['q'] ?? '';
      expect(q, contains('Frank Herbert'));
    });
  });
}
