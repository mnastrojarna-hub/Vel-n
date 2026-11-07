import 'package:flutter/material.dart';

/// Jméno + příjmení vedle sebe (jako dosud); když by se popisek pole do
/// poloviny šířky nevešel (úzký telefon + velké písmo: „Nachname“,
/// „Achternaam“ se ořízly), pole se skládají pod sebe.
class RegisterNameRow extends StatelessWidget {
  final Widget first, last;

  /// Popisky obou polí (pro měření).
  final List<String> labels;
  const RegisterNameRow({super.key, required this.first, required this.last, required this.labels});

  static const _gap = 9.0;

  bool _fits(BuildContext context, double width) {
    final theme = Theme.of(context);
    final style = (theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16))
        .merge(theme.inputDecorationTheme.labelStyle);
    final pad = theme.inputDecorationTheme.contentPadding?.horizontal ?? 32;
    final room = (width - _gap) / 2 - pad;
    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      if (w > room) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => _fits(context, c.maxWidth)
            ? Row(children: [
                Expanded(child: first),
                const SizedBox(width: _gap),
                Expanded(child: last),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                first,
                const SizedBox(height: _gap),
                last,
              ]),
      );
}
