import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cachy/data/services/obsidian_export.dart';
import 'package:cachy/domain/models/block.dart';
import 'package:cachy/domain/models/card.dart';
import 'package:flutter_test/flutter_test.dart';

Card _card(String id, String oneLiner, {List<Block> blocks = const []}) => Card(
      cardId: id,
      source: const Source(url: 'https://example.com/r'),
      base: Base(oneLiner: oneLiner, tags: const ['food', 'quick meals']),
      blocks: blocks,
    );

void main() {
  test('builds a zip with one note per card plus README', () {
    final zip = ObsidianExport.buildVault([
      _card('1', 'Pasta tips'),
      _card('2', 'Budget travel'),
    ]);
    final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name).toSet();
    expect(names, contains('Cachy/Pasta tips.md'));
    expect(names, contains('Cachy/Budget travel.md'));
    expect(names, contains('Cachy/README.md'));
  });

  test('dedupes notes with identical titles', () {
    final zip = ObsidianExport.buildVault([
      _card('1', 'Same'),
      _card('2', 'Same'),
    ]);
    final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name).toList();
    expect(names, contains('Cachy/Same.md'));
    expect(names, contains('Cachy/Same (2).md'));
  });

  test('renders blocks and tags as markdown', () {
    final zip = ObsidianExport.buildVault([
      _card('1', 'Recipe', blocks: const [
        BulletListBlock(id: 'b', items: ['eggs', 'flour']),
        ChecklistBlock(id: 'c', items: [
          ChecklistItem(text: 'mix', checked: true),
          ChecklistItem(text: 'bake'),
        ]),
      ]),
    ]);
    final note = ZipDecoder()
        .decodeBytes(zip)
        .files
        .firstWhere((f) => f.name == 'Cachy/Recipe.md');
    final md = utf8.decode(note.content as List<int>);
    expect(md, contains('# Recipe'));
    expect(md, contains('- eggs'));
    expect(md, contains('- [x] mix'));
    expect(md, contains('- [ ] bake'));
    expect(md, contains('#quick-meals'));
    expect(md, contains('tags:'));
  });
}
