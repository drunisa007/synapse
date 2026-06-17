import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../ui/synapse_tokens.dart';

class SynMarkdownText extends StatelessWidget {
  final String data;
  final double fontSize;
  final double lineHeight;
  final Color? color;
  final bool selectable;

  const SynMarkdownText({
    super.key,
    required this.data,
    this.fontSize = 13,
    this.lineHeight = 1.5,
    this.color,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? SynColors.text;
    final base = TextStyle(
      color: textColor,
      fontSize: fontSize,
      height: lineHeight,
    );

    return MarkdownBody(
      data: data.trim(),
      selectable: selectable,
      styleSheet: MarkdownStyleSheet(
        p: base,
        strong: base.copyWith(color: textColor, fontWeight: FontWeight.w700),
        em: base.copyWith(fontStyle: FontStyle.italic),
        a: base.copyWith(
          color: SynColors.cyan,
          decoration: TextDecoration.underline,
          decorationColor: SynColors.cyan,
        ),
        code: base.copyWith(
          color: SynColors.amber,
          fontFamily: 'monospace',
          fontSize: fontSize - 1,
          backgroundColor: SynColors.surfaceMuted,
        ),
        blockSpacing: SynSpacing.sm,
        listIndent: SynSpacing.xl,
        listBullet: base.copyWith(color: textColor),
        blockquote: base.copyWith(color: SynColors.textMuted),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: SynSpacing.md,
          vertical: SynSpacing.sm,
        ),
        blockquoteDecoration: BoxDecoration(
          color: SynColors.surfaceMuted,
          border: const Border(
            left: BorderSide(color: SynColors.borderStrong, width: 3),
          ),
          borderRadius: BorderRadius.circular(SynRadii.md),
        ),
        codeblockPadding: const EdgeInsets.all(SynSpacing.md),
        codeblockDecoration: BoxDecoration(
          color: SynColors.appBgAlt,
          border: Border.all(color: SynColors.border),
          borderRadius: BorderRadius.circular(SynRadii.md),
        ),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SynColors.border)),
        ),
      ),
      onTapLink: (_, __, ___) {
        // Deliberately do nothing: links are styled but not opened implicitly.
      },
    );
  }
}
