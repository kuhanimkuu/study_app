import 'package:flutter/material.dart';

import '../../../../../app/theme.dart' show monoTextStyle;

/// Renders a `{"type": "text", "content": "...", "source": "..."}` block.
/// Verified against the moderator's actual output (features/moderator/
/// engine.py) via real HTTP calls, not assumed from json.md alone.
///
/// The content is the model's own reply, which is Markdown-flavoured in
/// practice (found 2026-10-06 via live testing: "**Start with the
/// equation**: We have \\(2x + 3 = 7\\)") — rendered as plain `Text` it
/// showed literal asterisks and LaTeX delimiters. [MarkdownLite] handles
/// the subset models actually emit; anything else stays literal text.
class TextBlockView extends StatelessWidget {
  const TextBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final source = block['source'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownLite(block['content']?.toString() ?? ''),
          if (source != null && source != 'moderator')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('— $source', style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ),
    );
  }
}

/// A deliberately small Markdown renderer: `#`-headings, `-`/`*`/`1.`
/// list items, blank-line paragraph breaks, and inline `**bold**`,
/// `*italic*`, `` `code` `` and `\( math \)` / `$math$` (shown in the
/// mono font with delimiters removed — not typeset; block equations
/// already have their own EquationBlockView). Selectable so a student
/// can copy an answer.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.text, {super.key});

  final String text;

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^[-*•]\s+(.*)$');
  static final _numbered = RegExp(r'^(\d+)[.)]\s+(.*)$');
  static final _inline = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\\\((.+?)\\\)|\\\[(.+?)\\\]|\$([^$\n]+)\$|(?<![\w*])\*([^*\n]+)\*(?!\w)');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = DefaultTextStyle.of(context).style;
    final children = <Widget>[];

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }
      final h = _heading.firstMatch(line.trim());
      if (h != null) {
        final style = (h.group(1)!.length <= 2 ? theme.textTheme.titleMedium : theme.textTheme.titleSmall) ?? base;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text.rich(_spans(context, h.group(2)!, style.copyWith(fontWeight: FontWeight.w700))),
        ));
        continue;
      }
      final b = _bullet.firstMatch(line.trim());
      final n = b == null ? _numbered.firstMatch(line.trim()) : null;
      if (b != null || n != null) {
        final marker = b != null ? '•' : '${n!.group(1)}.';
        final body = b != null ? b.group(1)! : n!.group(2)!;
        final indent = (line.length - line.trimLeft().length) >= 2 ? 16.0 : 0.0;
        children.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 1, bottom: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Text(marker, style: base.copyWith(color: theme.colorScheme.primary))),
              Expanded(child: Text.rich(_spans(context, body, base))),
            ],
          ),
        ));
        continue;
      }
      children.add(Text.rich(_spans(context, line, base)));
    }

    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  TextSpan _spans(BuildContext context, String s, TextStyle style) {
    final mono = monoTextStyle(context, fontSize: (style.fontSize ?? 14) - 1, fontWeight: FontWeight.w500, color: style.color);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: mono));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(text: m.group(6), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else {
        final math = m.group(3) ?? m.group(4) ?? m.group(5)!;
        spans.add(TextSpan(text: _plainMath(math), style: mono));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return TextSpan(style: style, children: spans);
  }

  /// The handful of LaTeX commands that show up in short inline math,
  /// mapped to readable characters — e.g. `x \times 2` → `x × 2`.
  static String _plainMath(String latex) {
    const map = {
      r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\leq': '≤', r'\geq': '≥',
      r'\neq': '≠', r'\approx': '≈', r'\infty': '∞', r'\pi': 'π', r'\theta': 'θ', r'\alpha': 'α',
      r'\beta': 'β', r'\Delta': 'Δ', r'\to': '→', r'\rightarrow': '→', r'\sqrt': '√',
    };
    var out = latex.trim();
    map.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAllMapped(RegExp(r'\\frac\{([^}]*)\}\{([^}]*)\}'), (m) => '(${m[1]})/(${m[2]})');
    return out.replaceAll(RegExp(r'\\(left|right)'), '').replaceAll('{', '').replaceAll('}', '');
  }
}
