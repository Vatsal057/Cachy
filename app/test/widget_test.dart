// Contract tests for the schema mirror (docs/04). The block renderer's promise
// is that unknown/malformed blocks never crash — these guard that invariant.

import 'package:flutter_test/flutter_test.dart';

import 'package:cachy/data/repositories/card_repository.dart';
import 'package:cachy/domain/models/block.dart';
import 'package:cachy/domain/models/card.dart';
import 'package:cachy/domain/models/enums.dart';

void main() {
  group('Block.fromJson', () {
    test('dispatches each vocabulary type to its subtype', () {
      expect(Block.fromJson({'type': 'heading', 'id': 'b1', 'text': 'H'}),
          isA<HeadingBlock>());
      expect(Block.fromJson({'type': 'paragraph', 'id': 'b2', 'text': 'p'}),
          isA<ParagraphBlock>());
      expect(
          Block.fromJson({'type': 'bullet_list', 'id': 'b3', 'items': ['a']}),
          isA<BulletListBlock>());
      expect(
          Block.fromJson({
            'type': 'step_list',
            'id': 'b4',
            'steps': [
              {'text': 's', 'checkable': true}
            ]
          }),
          isA<StepListBlock>());
      expect(
          Block.fromJson({
            'type': 'checklist',
            'id': 'b5',
            'items': [
              {'text': 'milk', 'checked': false}
            ]
          }),
          isA<ChecklistBlock>());
      expect(
          Block.fromJson({
            'type': 'callout',
            'id': 'b6',
            'variant': 'warning',
            'text': 'careful',
            'confidence': 'low'
          }),
          isA<CalloutBlock>());
    });

    test('out-of-vocabulary type degrades to UnknownBlock', () {
      final block = Block.fromJson({'type': 'hologram', 'id': 'x', 'text': 'hi'});
      expect(block, isA<UnknownBlock>());
      expect((block as UnknownBlock).text, 'hi');
    });

    test('malformed payload does not throw and stays renderable', () {
      // step_list with the wrong shape for `steps` must not crash; it degrades
      // to a renderable (empty) block rather than throwing.
      final block = Block.fromJson({'type': 'step_list', 'id': 'b', 'steps': 'oops'});
      expect(block, isA<Block>());
      expect(block, isA<StepListBlock>());
      expect((block as StepListBlock).steps, isEmpty);
    });
  });

  group('Card.fromJson', () {
    test('parses a minimal processing card', () {
      final card = Card.fromJson({
        'card_id': 'c1',
        'state': 'processing',
        'source': {'url': 'https://insta/reel/1', 'platform': 'instagram'},
      });
      expect(card.cardId, 'c1');
      expect(card.state, CardState.processing);
      expect(card.isProcessing, isTrue);
      expect(card.source.platform, 'instagram');
      expect(card.blocks, isEmpty);
    });

    test('preserves rawBlocks for lossless PATCH round-trip', () {
      final card = Card.fromJson({
        'card_id': 'c2',
        'state': 'ready',
        'source': {'url': 'u'},
        'blocks': [
          {
            'type': 'checklist',
            'id': 'b1',
            'items': [
              {'text': 'eggs', 'checked': false}
            ]
          }
        ],
      });
      final patched = card.toggleChecklistItem('b1', 0, true);
      expect((patched.first['items'] as List).first['checked'], isTrue);
      // Original is untouched (deep copy).
      expect((card.rawBlocks.first['items'] as List).first['checked'], isFalse);
    });

    test('unknown content_type falls back to other', () {
      final card = Card.fromJson({
        'card_id': 'c3',
        'state': 'ready',
        'source': {'url': 'u'},
        'base': {'content_type': 'interpretive_dance'},
      });
      expect(card.base.contentType, ContentType.other);
    });

    test('action_items parse and round-trip through toJson (docs/13)', () {
      final card = Card.fromJson({
        'card_id': 'c4',
        'state': 'ready',
        'source': {'url': 'u'},
        'action_items': {
          'followed': true,
          'items': [
            {'id': 'a1', 'text': 'Drink water', 'done': true},
            {'id': 'a2', 'text': 'Sleep early', 'done': false},
          ],
        },
      });
      expect(card.actionItems.followed, isTrue);
      expect(card.actionItems.isPresent, isTrue);
      expect(card.actionItems.items.first.text, 'Drink water');
      expect(card.actionItems.items.first.done, isTrue);
      // Survives serialization for caching / PATCH.
      expect(card.actionItems.toJson(), {
        'followed': true,
        'items': [
          {'id': 'a1', 'text': 'Drink water', 'done': true},
          {'id': 'a2', 'text': 'Sleep early', 'done': false},
        ],
      });
    });

    test('missing action_items defaults to unfollowed empty', () {
      final card = Card.fromJson({
        'card_id': 'c5',
        'state': 'ready',
        'source': {'url': 'u'},
      });
      expect(card.actionItems.followed, isFalse);
      expect(card.actionItems.isPresent, isFalse);
    });
  });
}
