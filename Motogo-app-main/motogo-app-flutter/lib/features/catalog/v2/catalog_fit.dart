import 'package:flutter/widgets.dart';

import '../../../core/v2/widgets/mg_text_fit.dart';

/// Width of the longest word of [text] in [style] at the context's text
/// scale (verify:render: a layout picks a wider / stacked variant before a
/// word would have to break in half). [style] should already be merged
/// with `DefaultTextStyle` (font family). Shared `mg_text_fit.dart` (r2).
double catWordWidth(BuildContext context, String text, TextStyle style) =>
    mgWordWidth(context, text, style, merge: false);

/// Width of [text] on one line (no wrapping) in [style] at the context's
/// text scale.
double catLineWidth(BuildContext context, String text, TextStyle style) =>
    mgLineWidth(context, text, style, merge: false);
