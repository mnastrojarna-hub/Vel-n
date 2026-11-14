import 'package:flutter/widgets.dart';

import '../../../core/v2/widgets/mg_text_fit.dart';

/// true when every word of [text] fits [maxWidth] in [style] at [scaler]
/// (so wrapping never has to cut a word — verify:render "word-break").
/// Shared `mg_text_fit.dart` (r2).
bool homeWordsFit(String text, TextStyle style, double maxWidth, [TextScaler scaler = TextScaler.noScaling]) =>
    mgWordWidthWith(text, style, scaler) <= maxWidth;

/// [homeWordsFit] for the style as painted in [context] (inherited font
/// family + the current text size).
bool homeWordsFitIn(BuildContext context, String text, TextStyle style, double maxWidth) =>
    homeWordsFit(text, DefaultTextStyle.of(context).style.merge(style), maxWidth, MediaQuery.textScalerOf(context));

/// true when [text] (as painted in [context]) takes at most [lines] lines
/// at [maxWidth].
bool homeLinesFitIn(BuildContext context, String text, TextStyle style, double maxWidth, int lines) =>
    mgLinesFit(context, text, style, maxWidth, lines);
