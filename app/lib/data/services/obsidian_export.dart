/// Render the card library as an Obsidian vault — one markdown note per card,
/// zipped for the OS share sheet. Pure transform (no IO besides zipping bytes):
/// blocks become standard markdown, tags become `#tags` so the vault has a graph,
/// and YAML frontmatter carries source/metadata.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/models/block.dart';
import '../../domain/models/card.dart';

class ObsidianExport {
  /// Build a `.zip` of the vault from [cards]. Returns the zip bytes.
  static Uint8List buildVault(List<Card> cards) {
    final archive = Archive();
    final used = <String>{};

    for (final card in cards) {
      final name = _uniqueSlug(card, used);
      final md = utf8.encode(_noteFor(card));
      archive.addFile(ArchiveFile('Cachy/$name.md', md.length, md));
    }

    final readme = utf8.encode(_readme(cards.length));
    archive.addFile(ArchiveFile('Cachy/README.md', readme.length, readme));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // --- note rendering ------------------------------------------------------ //

  static String _noteFor(Card c) {
    final b = StringBuffer();
    final title = _title(c);

    // YAML frontmatter.
    b.writeln('---');
    b.writeln('title: ${_yaml(title)}');
    if (c.source.url.isNotEmpty) b.writeln('source: ${_yaml(c.source.url)}');
    if (c.source.platform != null) b.writeln('platform: ${_yaml(c.source.platform!)}');
    if (c.source.creator != null) b.writeln('creator: ${_yaml(c.source.creator!)}');
    b.writeln('type: ${c.base.contentType.name}');
    if (c.meta.createdAt != null) {
      b.writeln('created: ${c.meta.createdAt!.toIso8601String()}');
    }
    if (c.base.tags.isNotEmpty) {
      b.writeln('tags:');
      for (final t in c.base.tags) {
        b.writeln('  - ${_yaml(_tagSlug(t))}');
      }
    }
    b.writeln('---');
    b.writeln();

    b.writeln('# $title');
    b.writeln();
    if (c.base.oneLiner.isNotEmpty) {
      b.writeln('> ${c.base.oneLiner}');
      b.writeln();
    }
    if (c.base.tldr.isNotEmpty) {
      b.writeln(c.base.tldr);
      b.writeln();
    }

    for (final block in c.blocks) {
      final rendered = _block(block);
      if (rendered.isNotEmpty) {
        b.writeln(rendered);
        b.writeln();
      }
    }

    if (c.actionItems.isPresent) {
      b.writeln('## Actions');
      for (final item in c.actionItems.items) {
        b.writeln('- [${item.done ? 'x' : ' '}] ${item.text}');
      }
      b.writeln();
    }

    final rh = c.insight?.rabbitHole;
    if (rh != null && !rh.isEmpty) {
      b.writeln('## Rabbit hole');
      for (final q in rh.questions) {
        b.writeln('- $q');
      }
      for (final t in rh.adjacentTopics) {
        b.writeln('- [[${_tagSlug(t)}]]');
      }
      for (final a in rh.advancedConcepts) {
        b.writeln('- [[${_tagSlug(a)}]]');
      }
      b.writeln();
    }

    if (c.source.url.isNotEmpty) {
      b.writeln('---');
      b.writeln('[Original reel](${c.source.url})');
    }
    if (c.base.tags.isNotEmpty) {
      b.writeln();
      b.writeln(c.base.tags.map((t) => '#${_tagSlug(t)}').join(' '));
    }

    return b.toString();
  }

  static String _block(Block block) {
    switch (block) {
      case HeadingBlock b:
        final level = b.level.clamp(2, 6);
        return '${'#' * level} ${b.text}';
      case ParagraphBlock b:
        return b.text;
      case BulletListBlock b:
        return b.items.map((i) => '- $i').join('\n');
      case StepListBlock b:
        return b.steps
            .map((s) => s.checkable
                ? '- [${s.checked ? 'x' : ' '}] ${s.text}'
                : '1. ${s.text}')
            .join('\n');
      case KeyValueBlock b:
        return b.pairs.map((p) => '- **${p.key}:** ${p.value}').join('\n');
      case ChecklistBlock b:
        return b.items
            .map((i) => '- [${i.checked ? 'x' : ' '}] ${i.text}')
            .join('\n');
      case CalloutBlock b:
        // Obsidian callout syntax.
        return '> [!${b.variant}]\n> ${b.text.replaceAll('\n', '\n> ')}';
      case LinkBlock b:
        return '[${b.label ?? b.url}](${b.url})';
      case MapBlock b:
        return b.places
            .map((p) => '- **${p.name}**${p.note.isNotEmpty ? ' — ${p.note}' : ''}')
            .join('\n');
      case TableBlock b:
        return _table(b);
      case UnknownBlock b:
        if (b.text != null && b.text!.isNotEmpty) return b.text!;
        if (b.items.isNotEmpty) return b.items.map((i) => '- $i').join('\n');
        return '';
    }
  }

  static String _table(TableBlock b) {
    if (b.headers.isEmpty) return '';
    final out = StringBuffer();
    out.writeln('| ${b.headers.join(' | ')} |');
    out.writeln('| ${b.headers.map((_) => '---').join(' | ')} |');
    for (final row in b.rows) {
      out.writeln('| ${row.join(' | ')} |');
    }
    return out.toString().trimRight();
  }

  static String _readme(int count) =>
      '# Cachy export\n\n$count card(s) exported as an Obsidian vault. '
      'Open the `Cachy` folder as a vault in Obsidian.\n';

  // --- helpers ------------------------------------------------------------- //

  static String _title(Card c) {
    final raw = c.base.oneLiner.trim().isNotEmpty
        ? c.base.oneLiner.trim()
        : (c.source.caption.trim().isNotEmpty
            ? c.source.caption.trim()
            : 'Card ${c.cardId}');
    // First line only; titles spanning lines break the heading.
    return raw.split('\n').first;
  }

  /// Filesystem- and Obsidian-link-safe note name.
  static String _uniqueSlug(Card c, Set<String> used) {
    var slug = _title(c)
        .replaceAll(RegExp(r'[\\/:*?"<>|\[\]#^]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (slug.length > 80) slug = slug.substring(0, 80).trim();
    if (slug.isEmpty) slug = 'card-${c.cardId}';
    var candidate = slug;
    var n = 2;
    while (!used.add(candidate.toLowerCase())) {
      candidate = '$slug ($n)';
      n++;
    }
    return candidate;
  }

  static String _tagSlug(String t) => t.trim().replaceAll(RegExp(r'\s+'), '-');

  static String _yaml(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
