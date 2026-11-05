import 'package:flutter/widgets.dart';

import '../../../core/v2/flag/v2_scope.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

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

/// v2 look of a timeline event row of `ResModificationHistory` (label left,
/// date right); null in the old look (the caller keeps its own row). The
/// label wraps at spaces with an 8 dp gap before the date; when a word of
/// the label would not fit beside the date even at 80 %, the date moves
/// under the label — whatever the date's width (nl / de / uk at 320 dp,
/// large text, wide dates like 28.12.2026 23:58).
Widget? resV2EventRow(BuildContext context, Text label, Text date) =>
    MgV2.on(context) ? _ResEventRowV2(label: label, date: date) : null;

class _ResEventRowV2 extends StatelessWidget {
  final Text label;
  final Text date;
  const _ResEventRowV2({required this.label, required this.date});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final dateW = resLineWidth(context, date.data ?? '', date.style ?? const TextStyle());
        final rest = c.maxWidth - dateW - 8;
        if (rest > 0 && resWordsFit(context, label.data ?? '', label.style ?? const TextStyle(), rest, minScale: 0.8)) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: MgWordFit(child: label)),
            const SizedBox(width: 8),
            date,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgWordFit(child: label),
          const SizedBox(height: 2),
          date,
        ]);
      });
}
