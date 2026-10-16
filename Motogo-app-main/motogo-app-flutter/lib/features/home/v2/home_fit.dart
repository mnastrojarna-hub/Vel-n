import 'package:flutter/widgets.dart';

/// true when every word of [text] fits [maxWidth] in [style] at [scaler]
/// (so wrapping never has to cut a word — verify:render "word-break").
bool homeWordsFit(String text, TextStyle style, double maxWidth, [TextScaler scaler = TextScaler.noScaling]) {
  for (final w in text.split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    final tp = TextPainter(
        text: TextSpan(text: w, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
      ..layout();
    final width = tp.width;
    tp.dispose();
    if (width > maxWidth) return false;
  }
  return true;
}

/// [homeWordsFit] for the style as painted in [context] (inherited font
/// family + the current text size).
bool homeWordsFitIn(BuildContext context, String text, TextStyle style, double maxWidth) =>
    homeWordsFit(text, DefaultTextStyle.of(context).style.merge(style), maxWidth, MediaQuery.textScalerOf(context));
