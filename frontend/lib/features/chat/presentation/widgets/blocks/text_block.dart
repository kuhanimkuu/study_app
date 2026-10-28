import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
/// `*italic*` and `` `code` ``. Selectable so a student can copy an answer.
///
/// Maths is typeset like a textbook (2026-10-28; it used to be the code
/// font with half the LaTeX left in): `\( … \)` and `$…$` inline, at the
/// size and colour of the text around it, and `\[ … \]` / `$$ … $$` as a
/// centred equation that scrolls sideways when it's too wide. A bare
/// `x^2` in ordinary text becomes x². Anything the typesetter can't read
/// falls back to readable symbols in the normal font.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.text, {super.key});

  final String text;

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^[-*•]\s+(.*)$');
  static final _numbered = RegExp(r'^(\d+)[.)]\s+(.*)$');
  // Groups: 1 bold, 2 code, 3 \( \), 4 \[ \], 5 $$ $$, 6 $ $, 7 italic.
  // A lone `$` needs no space just inside it and no digit after it, so
  // prices ("$5 and $10") stay text.
  static final _inline = RegExp(
    r'\*\*(.+?)\*\*|`([^`]+)`|\\\((.+?)\\\)|\\\[(.+?)\\\]|\$\$(.+?)\$\$|\$(?=\S)([^$\n]+?)(?<=\S)\$(?!\d)|(?<![\w*])\*([^*\n]+)\*(?!\w)',
  );
  // A whole line that is one displayed equation.
  static final _displayLine = RegExp(r'^(?:\\\[(.+)\\\]|\$\$(.+)\$\$)$');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = DefaultTextStyle.of(context).style;
    final children = <Widget>[];

    // Fenced blocks (2026-10-27): ``` code, and \[ … \] maths spread over
    // several lines. Fuller answers use both, and they showed up as raw
    // backticks and backslashes.
    List<String>? fenced;
    var fenceIsMath = false;
    var mathClose = r'\]';
    void closeFence() {
      final body = fenced!.join('\n');
      children.add(fenceIsMath ? _mathBlock(context, body) : _codeBlock(context, body));
      fenced = null;
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (fenced != null) {
        final closes = fenceIsMath ? trimmed.endsWith(mathClose) : trimmed.startsWith('```');
        if (closes) {
          if (fenceIsMath && trimmed != mathClose) fenced!.add(trimmed.substring(0, trimmed.length - 2));
          closeFence();
        } else {
          fenced!.add(fenceIsMath ? trimmed : raw);
        }
        continue;
      }
      if (trimmed.startsWith('```')) {
        fenced = [];
        fenceIsMath = false;
        continue;
      }
      if ((trimmed.startsWith(r'\[') && !trimmed.contains(r'\]')) ||
          (trimmed.startsWith(r'$$') && !trimmed.substring(2).contains(r'$$'))) {
        mathClose = trimmed.startsWith(r'$$') ? r'$$' : r'\]';
        fenced = [if (trimmed.length > 2) trimmed.substring(2)];
        fenceIsMath = true;
        continue;
      }
      final display = _displayLine.firstMatch(trimmed);
      if (display != null) {
        children.add(_mathBlock(context, display.group(1) ?? display.group(2)!));
        continue;
      }
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
    if (fenced != null) closeFence(); // an unclosed fence still shows its content

    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  TextSpan _spans(BuildContext context, String s, TextStyle style) {
    final mono = monoTextStyle(context, fontSize: (style.fontSize ?? 14) - 1, fontWeight: FontWeight.w500, color: style.color);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: superscripts(s.substring(last, m.start))));
      if (m.group(1) != null) {
        spans.add(TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w700),
          children: _spans(context, m.group(1)!, style.copyWith(fontWeight: FontWeight.w700)).children,
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: mono));
      } else if (m.group(7) != null) {
        spans.add(TextSpan(text: superscripts(m.group(7)!), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else {
        final latex = m.group(3) ?? m.group(4) ?? m.group(5) ?? m.group(6)!;
        spans.add(_inlineMath(context, latex, style));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: superscripts(s.substring(last))));
    return TextSpan(style: style, children: spans);
  }

  /// Typeset maths sitting on the line of text, on its baseline and in its
  /// colour. KaTeX's letters are smaller than the app font's at the same
  /// size, so it's scaled up to match; fractions are full size (`\dfrac`),
  /// as squashed ones are hard to read on a phone. A long expression
  /// scrolls sideways instead of running off the screen.
  InlineSpan _inlineMath(BuildContext context, String latex, TextStyle style) {
    final color = style.color ?? DefaultTextStyle.of(context).style.color;
    final textStyle = TextStyle(fontSize: (style.fontSize ?? 14) * 1.18, color: color);
    final tex = latex.trim().replaceAll(RegExp(r'\\frac(?![a-zA-Z])'), r'\dfrac');
    final math = Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: textStyle,
      onErrorFallback: (_) => Text(plainMath(latex), style: style.copyWith(fontStyle: FontStyle.italic)),
    );
    if (tex.length <= 40) {
      return WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: math);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: math),
      ),
    );
  }

  /// A code sample: monospace, kept on its own lines, scrolling sideways
  /// rather than wrapping (indentation matters in code).
  Widget _codeBlock(BuildContext context, String code) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(code, style: monoTextStyle(context, fontSize: 13, color: theme.colorScheme.onSurface)),
      ),
    );
  }

  /// A displayed equation, typeset and centred; a wide one scrolls sideways.
  Widget _mathBlock(BuildContext context, String latex) {
    final color = DefaultTextStyle.of(context).style.color;
    final textStyle = TextStyle(fontSize: 17, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            latex.trim(),
            mathStyle: MathStyle.display,
            textStyle: textStyle,
            onErrorFallback: (_) => Text(plainMath(latex), textAlign: TextAlign.center, style: textStyle),
          ),
        ),
      ),
    );
  }
}

const _superscriptDigits = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', '-': '⁻',
};

/// `x^2`, `10^-3`, `m^{12}` in ordinary text → x², 10⁻³, m¹² (only whole
/// numbers, which have proper superscript characters).
String superscripts(String text) => text.replaceAllMapped(
      RegExp(r'(?<=[\w)\]])\^(?:\{(-?\d{1,3})\}|(-?\d{1,3})(?!\d|\.\d))'),
      (m) => (m[1] ?? m[2])!.split('').map((c) => _superscriptDigits[c]!).join(),
    );

/// Readable text for LaTeX the typesetter couldn't handle: common commands
/// as their symbols, fractions as a/b, powers as superscripts, and no
/// leftover backslashes or braces.
String plainMath(String latex) {
  const map = {
    r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\leq': '≤', r'\le': '≤', r'\geq': '≥',
    r'\ge': '≥', r'\neq': '≠', r'\approx': '≈', r'\infty': '∞', r'\pi': 'π', r'\theta': 'θ', r'\alpha': 'α',
    r'\beta': 'β', r'\gamma': 'γ', r'\lambda': 'λ', r'\mu': 'μ', r'\sigma': 'σ', r'\omega': 'ω',
    r'\Delta': 'Δ', r'\Sigma': 'Σ', r'\sum': 'Σ', r'\int': '∫', r'\partial': '∂', r'\rightarrow': '→',
    r'\to': '→', r'\Rightarrow': '⇒', r'\sqrt': '√', r'\degree': '°', r'\circ': '°',
  };
  var out = latex.trim();
  out = out.replaceAllMapped(RegExp(r'\\(?:text|mathrm|mathbf|operatorname)\{([^}]*)\}'), (m) => m[1]!);
  out = out.replaceAllMapped(RegExp(r'\\[dt]?frac\{([^}]*)\}\{([^}]*)\}'), (m) {
    String wrap(String t) => t.length > 1 ? '($t)' : t;
    return '${wrap(m[1]!)}/${wrap(m[2]!)}';
  });
  // Longest names first, so \leq isn't read as \le + q.
  final names = map.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    out = out.replaceAllMapped(RegExp(RegExp.escape(name) + r'(?![a-zA-Z])'), (_) => map[name]!);
  }
  out = superscripts(out);
  out = out.replaceAll(RegExp(r'\\[,;:! ]'), ' ').replaceAll(RegExp(r'\\(left|right)'), '');
  return out.replaceAll(RegExp(r'\\(?=[a-zA-Z])'), '').replaceAll('{', '').replaceAll('}', '').replaceAll(RegExp(r' {2,}'), ' ');
}
