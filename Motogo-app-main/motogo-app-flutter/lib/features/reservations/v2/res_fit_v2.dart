import 'package:flutter/widgets.dart';

import '../../../core/v2/widgets/mg_text_fit.dart';

/// verify:render helpers of the Rezervace v2 layouts: a row picks its
/// stacked / two-line variant BEFORE a word would have to break in half
/// (de / nl / fr / uk / pl labels at 320 dp or with large text). Thin names
/// over the shared `mg_text_fit.dart` (r2).

/// Width of the longest word of [text] as painted in [context] ([style]
/// merged with the inherited text style, at the current text size).
double resWordWidth(BuildContext context, String text, TextStyle style) => mgWordWidth(context, text, style);

/// Width of [text] on one line as painted in [context].
double resLineWidth(BuildContext context, String text, TextStyle style) => mgLineWidth(context, text, style);

/// true when every word of [text] fits [width] — scaled down to [minScale]
/// at most (= what `MgWordFit(minScale:)` around the label does).
bool resWordsFit(BuildContext context, String text, TextStyle style, double width, {double minScale = 1}) =>
    mgWordsFit(context, text, style, width, minScale: minScale);

/// true when [text] fits [width] on ONE line, scaled down to [minScale] at most.
bool resLineFits(BuildContext context, String text, TextStyle style, double width, {double minScale = 1}) =>
    mgLineFits(context, text, style, width, minScale: minScale);
