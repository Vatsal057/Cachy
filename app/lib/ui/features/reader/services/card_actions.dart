/// The action layer (docs/13): turns a card into things the device can do.
/// Actions are **content-aware** — derived from the blocks a card actually has,
/// not just its content_type — plus a common set offered on every card. Every
/// payload is built client-side from existing blocks, so nothing here needs a
/// schema change. All handlers are best-effort and never crash the reader.
library;

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/models/block.dart';
import '../../../../domain/models/card.dart';

/// Outcome of an action so the UI can show the right message.
enum ActionResult { done, copied, empty, failed }

/// Every side-effect action the action layer can perform. (Chat/"Ask" is a
/// navigation concern handled by the reader, not a side-effect, so it's not here.)
enum CardActionType {
  copy,
  share,
  openOriginal,
  addToCalendar,
  shoppingList,
  openMaps,
  openLinks,
}

/// A presentable action: what to label it and which icon to show.
class CardActionSpec {
  const CardActionSpec(this.type, this.label, this.icon);
  final CardActionType type;
  final String label;
  final PhosphorIconData icon;
}

class CardActions {
  const CardActions();

  /// The ordered, content-aware action set for a card. Common actions first,
  /// then ones unlocked by the blocks this card actually contains.
  List<CardActionSpec> available(Card card) {
    final out = <CardActionSpec>[
      const CardActionSpec(CardActionType.copy, 'Copy', PhosphorIconsRegular.copy),
      const CardActionSpec(CardActionType.share, 'Share', PhosphorIconsRegular.export),
      const CardActionSpec(
          CardActionType.addToCalendar, 'Add to calendar', PhosphorIconsRegular.calendar),
    ];
    if (_hasPlace(card)) {
      out.add(const CardActionSpec(
          CardActionType.openMaps, 'Open in Maps', PhosphorIconsRegular.mapPin));
    }
    if (_hasListItems(card)) {
      out.add(const CardActionSpec(CardActionType.shoppingList, 'Shopping list',
          PhosphorIconsRegular.shoppingCart));
    }
    if (_hasLinks(card)) {
      out.add(const CardActionSpec(
          CardActionType.openLinks, 'Open links', PhosphorIconsRegular.link));
    }
    if (card.source.url.isNotEmpty) {
      out.add(const CardActionSpec(CardActionType.openOriginal, 'Open original',
          PhosphorIconsRegular.playCircle));
    }
    return out;
  }

  /// Map the server-derived primary action to a concrete handler so the big
  /// primary button runs through the same dispatch as the secondary set.
  CardActionType? primaryType(Card card) {
    switch (card.primaryAction.kind.name) {
      case 'export':
        return CardActionType.share;
      case 'shoppingList':
        return CardActionType.shoppingList;
      case 'savePlace':
        return CardActionType.openMaps;
      case 'reminder':
      case 'schedule':
        return CardActionType.addToCalendar;
      default:
        return null;
    }
  }

  Future<ActionResult> perform(Card card, CardActionType type) async {
    try {
      switch (type) {
        case CardActionType.copy:
          return _copy(card);
        case CardActionType.share:
          return _share(_cardToMarkdown(card), card.base.oneLiner);
        case CardActionType.openOriginal:
          return _launch(card.source.url);
        case CardActionType.addToCalendar:
          return _addToCalendar(card);
        case CardActionType.shoppingList:
          return _shareShoppingList(card);
        case CardActionType.openMaps:
          return _openInMaps(card);
        case CardActionType.openLinks:
          return _openLinks(card);
      }
    } catch (_) {
      return ActionResult.failed;
    }
  }

  // --- block predicates -------------------------------------------------- //

  bool _hasPlace(Card card) =>
      card.blocks.any((b) => b is MapBlock && b.places.isNotEmpty);

  bool _hasListItems(Card card) => card.blocks.any(
      (b) => b is ChecklistBlock || b is BulletListBlock);

  bool _hasLinks(Card card) => card.blocks.any((b) => b is LinkBlock);

  // --- handlers ---------------------------------------------------------- //

  Future<ActionResult> _copy(Card card) async {
    final text = _cardToMarkdown(card);
    if (text.trim().isEmpty) return ActionResult.empty;
    await Clipboard.setData(ClipboardData(text: text));
    return ActionResult.copied;
  }

  Future<ActionResult> _share(String text, String subject) async {
    if (text.trim().isEmpty) return ActionResult.empty;
    await Share.share(text, subject: subject.isEmpty ? 'Cachy card' : subject);
    return ActionResult.done;
  }

  Future<ActionResult> _launch(String url) async {
    if (url.trim().isEmpty) return ActionResult.empty;
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    return ok ? ActionResult.done : ActionResult.failed;
  }

  Future<ActionResult> _shareShoppingList(Card card) async {
    final items = <String>[];
    for (final b in card.blocks) {
      if (b is ChecklistBlock) {
        items.addAll(b.items.map((i) => i.text));
      } else if (b is BulletListBlock) {
        items.addAll(b.items);
      }
    }
    final clean = items.where((i) => i.trim().isNotEmpty).toList();
    if (clean.isEmpty) return ActionResult.empty;
    final title = card.base.oneLiner.isEmpty ? 'Shopping list' : card.base.oneLiner;
    final body = '$title\n\n${clean.map((i) => '- [ ] $i').join('\n')}';
    return _share(body, title);
  }

  Future<ActionResult> _openInMaps(Card card) async {
    Place? place;
    for (final b in card.blocks) {
      if (b is MapBlock && b.places.isNotEmpty) {
        place = b.places.first;
        break;
      }
    }
    final query = place?.name ?? card.base.oneLiner;
    if (query.trim().isEmpty) return ActionResult.empty;
    final Uri uri;
    if (place?.lat != null && place?.lng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${place!.lat},${place.lng}',
      );
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
      );
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return ok ? ActionResult.done : ActionResult.failed;
  }

  Future<ActionResult> _openLinks(Card card) async {
    final urls = card.blocks
        .whereType<LinkBlock>()
        .map((b) => b.url)
        .where((u) => u.trim().isNotEmpty)
        .toList();
    if (urls.isEmpty) return ActionResult.empty;
    // Open the first link; the rest stay visible as tappable link blocks.
    return _launch(urls.first);
  }

  Future<ActionResult> _addToCalendar(Card card) async {
    final title = card.base.oneLiner.isEmpty ? 'Cachy reminder' : card.base.oneLiner;
    final start = DateTime.now().add(const Duration(days: 1));
    final desc = [card.base.tldr, card.source.url]
        .where((s) => s.trim().isNotEmpty)
        .join('\n\n');
    final event = Event(
      title: title,
      description: desc,
      startDate: start,
      endDate: start.add(const Duration(hours: 1)),
    );
    final ok = await Add2Calendar.addEvent2Cal(event);
    return ok ? ActionResult.done : ActionResult.failed;
  }

  // --- markdown serialization (copy / share) ----------------------------- //

  String _cardToMarkdown(Card card) {
    final out = <String>[];
    if (card.base.oneLiner.isNotEmpty) out.add('# ${card.base.oneLiner}');
    if (card.base.tldr.isNotEmpty) out.add('> ${card.base.tldr}');
    for (final b in card.blocks) {
      out.add(_blockToMarkdown(b));
    }
    if (card.source.url.isNotEmpty) {
      out.add('---\nSource: ${card.source.url}');
    }
    return out.where((s) => s.trim().isNotEmpty).join('\n\n');
  }

  String _blockToMarkdown(Block b) {
    switch (b) {
      case HeadingBlock(:final text, :final level):
        return '${'#' * level.clamp(1, 6)} $text';
      case ParagraphBlock(:final text):
        return text;
      case BulletListBlock(:final items):
        return items.map((i) => '- $i').join('\n');
      case StepListBlock(:final steps):
        return steps
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value.text}')
            .join('\n');
      case KeyValueBlock(:final pairs):
        return pairs.map((p) => '**${p.key}:** ${p.value}').join('\n');
      case ChecklistBlock(:final items):
        return items
            .map((i) => '- [${i.checked ? 'x' : ' '}] ${i.text}')
            .join('\n');
      case CalloutBlock(:final text):
        return '> $text';
      case LinkBlock(:final url, :final label):
        return '[${label ?? url}]($url)';
      case MapBlock(:final places):
        return places
            .map((p) => '- ${p.name}${p.note.isEmpty ? '' : ' — ${p.note}'}')
            .join('\n');
      case TableBlock(:final headers, :final rows):
        final head = '| ${headers.join(' | ')} |';
        final sep = '| ${headers.map((_) => '---').join(' | ')} |';
        final body = rows.map((r) => '| ${r.join(' | ')} |').join('\n');
        return '$head\n$sep\n$body';
      case UnknownBlock(:final text):
        return text ?? '';
    }
  }
}
