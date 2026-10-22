import 'package:flutter/widgets.dart';

/// verify:render helpers of the Profil v2 layouts: a layout picks its
/// stacked / one-column variant BEFORE a word would have to break in half
/// (de / nl / uk / pl labels at 320 dp or large text).

TextPainter _painter(BuildContext context, String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();

/// Width of the longest word of [text] as painted in [context] ([style]
/// merged with the inherited text style, at the current text size).
double pfWordWidth(BuildContext context, String text, TextStyle style) {
  var max = 0.0;
  for (final w in text.split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    final tp = _painter(context, w, style);
    if (tp.width > max) max = tp.width;
    tp.dispose();
  }
  return max;
}

/// Width of [text] on one line as painted in [context].
double pfLineWidth(BuildContext context, String text, TextStyle style) {
  final tp = _painter(context, text, style);
  final w = tp.width;
  tp.dispose();
  return w;
}

/// true when every word of [text] fits [width] — scaled down to [minScale]
/// at most (= what `MgWordFit(minScale:)` around the label does).
bool pfWordsFit(BuildContext context, String text, TextStyle style, double width, {double minScale = 1}) =>
    pfWordWidth(context, text, style) * minScale <= width;
