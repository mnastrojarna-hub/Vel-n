import 'package:flutter/widgets.dart';

/// Shared verify:render text measuring of the v2 layouts (r2: one copy
/// instead of five — profile / reservations / catalog / home / booking
/// keep their old names as thin wrappers). A layout uses these to pick its
/// stacked / wider variant BEFORE a word would have to break in half, and
/// they agree with what `MgWordFit(minScale:)` does around a label.
///
/// [merge] = merge [style] with the inherited `DefaultTextStyle` (font
/// family) — pass false when the caller already merged it.

TextStyle _painted(BuildContext context, TextStyle style, bool merge) =>
    merge ? DefaultTextStyle.of(context).style.merge(style) : style;

TextPainter _painter(String text, TextStyle style, TextScaler scaler, TextDirection dir, int? maxLines) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: dir,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout();

TextDirection _dir(BuildContext context) => Directionality.maybeOf(context) ?? TextDirection.ltr;

/// Width of the longest space-separated word of [text] in [style] at
/// [scaler] (no context: callers with their own style / scale).
double mgWordWidthWith(String text, TextStyle style, TextScaler scaler,
    [TextDirection dir = TextDirection.ltr]) {
  var max = 0.0;
  for (final w in text.split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    final tp = _painter(w, style, scaler, dir, 1);
    if (tp.width > max) max = tp.width;
    tp.dispose();
  }
  return max;
}

/// Width of the longest word of [text] as painted in [context] (font,
/// current text size).
double mgWordWidth(BuildContext context, String text, TextStyle style, {bool merge = true}) =>
    mgWordWidthWith(text, _painted(context, style, merge), MediaQuery.textScalerOf(context), _dir(context));

/// Width of [text] on ONE line as painted in [context].
double mgLineWidth(BuildContext context, String text, TextStyle style, {bool merge = true}) {
  final tp = _painter(text, _painted(context, style, merge), MediaQuery.textScalerOf(context), _dir(context), 1);
  final w = tp.width;
  tp.dispose();
  return w;
}

/// Longest unbreakable run (`minIntrinsicWidth`: no-break spaces join
/// words) and widest line (`maxIntrinsicWidth`) of [text] in [context].
(double, double) mgRunWidths(BuildContext context, String text, TextStyle style, {bool merge = true}) {
  final tp = _painter(text, _painted(context, style, merge), MediaQuery.textScalerOf(context), _dir(context), null);
  final r = (tp.minIntrinsicWidth, tp.maxIntrinsicWidth);
  tp.dispose();
  return r;
}

/// true when every word of [text] fits [width] — scaled down to [minScale]
/// at most (= what `MgWordFit(minScale:)` around the label does).
bool mgWordsFit(BuildContext context, String text, TextStyle style, double width, {double minScale = 1}) =>
    mgWordWidth(context, text, style) * minScale <= width;

/// true when [text] fits [width] on ONE line, scaled down to [minScale] at most.
bool mgLineFits(BuildContext context, String text, TextStyle style, double width, {double minScale = 1}) =>
    mgLineWidth(context, text, style) * minScale <= width;

/// true when [text] (as painted in [context]) takes at most [lines] lines
/// at [maxWidth].
bool mgLinesFit(BuildContext context, String text, TextStyle style, double maxWidth, int lines,
    {TextDirection dir = TextDirection.ltr}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: _painted(context, style, true)),
    textDirection: dir,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: lines,
  )..layout(maxWidth: maxWidth < 1 ? 1 : maxWidth);
  final ok = !tp.didExceedMaxLines;
  tp.dispose();
  return ok;
}
