/// Shared inline rich-text renderer for LLM-generated prose. Parses a small
/// inline-markdown subset — **bold**, *italic* / _italic_, `code` — plus
/// `[[Reference]]` markers that resolve to tappable card artifacts when a
/// [ReferenceScope] is in the tree. Used by the block renderer (cards) and the
/// chat bubbles, so emphasis renders identically everywhere LLM text appears.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/artifact.dart';

/// Inline grammar: `[[Reference]]`, then **bold**, *italic* / _italic_, `code`.
final _richPattern = RegExp(
  r'\[\[(.+?)\]\]|\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`',
  dotAll: true,
);

/// Carries the card's inline-reference resolver down to rich-text widgets, so a
/// `[[Name]]` marker becomes a tappable link without drilling params everywhere.
class ReferenceScope extends InheritedWidget {
  const ReferenceScope({
    super.key,
    required this.refs,
    required this.onTap,
    required super.child,
  });

  final Map<String, CatalogEntry> refs; // normalised title -> entry
  final void Function(CatalogEntry) onTap;

  CatalogEntry? resolve(String label) => refs[label.toLowerCase().trim()];

  static ReferenceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReferenceScope>();

  @override
  bool updateShouldNotify(ReferenceScope old) => old.refs != refs;
}

/// Drop-in for `Text` rendering the inline subset above. Stateful so tap
/// recognizers for `[[Name]]` references are disposed properly. With no
/// [ReferenceScope] in the tree (e.g. chat), refs render as their bare name.
class RichInlineText extends StatefulWidget {
  const RichInlineText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  State<RichInlineText> createState() => _RichInlineTextState();
}

class _RichInlineTextState extends State<RichInlineText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers(); // rebuilt fresh each build
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final scope = ReferenceScope.maybeOf(context);
    return Text.rich(TextSpan(children: _spans(widget.text, base, scope)));
  }

  List<InlineSpan> _spans(String text, TextStyle? base, ReferenceScope? scope) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _richPattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      final ref = m.group(1);
      if (ref != null) {
        spans.add(_referenceSpan(ref, base, scope));
      } else if (m.group(2) != null || m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(2) ?? m.group(3),
          style: base?.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (m.group(4) != null || m.group(5) != null) {
        spans.add(TextSpan(
          text: m.group(4) ?? m.group(5),
          style: base?.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(
          text: m.group(6),
          style: base?.copyWith(
            fontFamily: 'monospace',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return spans;
  }

  /// A `[[Name]]` marker: a tappable link if it resolves to a card artifact,
  /// otherwise the bare name (brackets stripped) so unknown refs never leak.
  InlineSpan _referenceSpan(String label, TextStyle? base, ReferenceScope? scope) {
    final entry = scope?.resolve(label);
    if (entry == null) return TextSpan(text: label, style: base);
    final recognizer = TapGestureRecognizer()..onTap = () => scope!.onTap(entry);
    _recognizers.add(recognizer);
    return TextSpan(
      text: label,
      style: base?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      recognizer: recognizer,
    );
  }
}
