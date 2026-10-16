import 'package:flutter/widgets.dart';

/// Width of the longest word of [text] in [style] at the context's text
/// scale (verify:render: a layout picks a wider / stacked variant before a
/// word would have to break in half). [style] should already be merged
/// with `DefaultTextStyle` (font family).
double catWordWidth(BuildContext context, String text, TextStyle style) {
  final scaler = MediaQuery.textScalerOf(context);
  final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
  var max = 0.0;
  for (final w in text.split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    final tp = TextPainter(text: TextSpan(text: w, style: style), textDirection: dir, textScaler: scaler)..layout();
    if (tp.width > max) max = tp.width;
    tp.dispose();
  }
  return max;
}

/// Width of [text] on one line (no wrapping) in [style] at the context's
/// text scale.
double catLineWidth(BuildContext context, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}
