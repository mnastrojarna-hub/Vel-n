import 'package:flutter/widgets.dart';

import '../../../core/v2/flag/v2_scope.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'res_fit_v2.dart';

/// v2 seams of old reservation widgets shown inside the v2 look (gear rows
/// of the edit — `EditGearSizePicker`, the paid add-on cards of
/// `EditExtrasSection` — and the `ResModificationHistory` title): the SAME
/// texts, styles and taps, laid out so no word splits in half and nothing
/// overflows (uk / de / nl / fr at 320 dp, large text). The old look stays
/// exactly as it was.

/// Header of a gear size picker: icon + name on the left, "chosen size" +
/// "ZDARMA" on the right — the right part moves under the name when both
/// do not fit one line.
class EditGearHeaderV2 extends StatelessWidget {
  final Widget icon;
  final Text label;
  final List<Text> trailing;
  const EditGearHeaderV2({super.key, required this.icon, required this.label, required this.trailing});

  // Plná šířka jako dřívější Row se Spacer: rámeček výběru velikosti se
  // nezúží na obsah a pravá část zůstane vpravo.
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              icon,
              const SizedBox(width: 6),
              Flexible(child: MgWordFit(child: label)),
            ]),
            if (trailing.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < trailing.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Flexible(child: MgWordFit(child: trailing[i])),
                ],
              ]),
          ],
        ),
      );
}

/// [text] as a flexible child of a `Row` in the v2 look (wraps at spaces,
/// whole words) instead of overflowing it; the old look gets [text] as is.
Widget resV2RowText(BuildContext context, Widget text) =>
    MgV2.on(context) ? Flexible(child: MgWordFit(child: text)) : text;

/// Body of a paid add-on card (`EditExtrasSection._paidCard`): checkbox,
/// name + state line and the price on the right — the price moves under
/// the texts when the name would otherwise split in half (uk „Спорядження
/// пасажира" at 320 dp, large text).
class EditPaidRowV2 extends StatelessWidget {
  final Widget checkbox;
  final Text label;
  final Text sub;
  final Text price;
  const EditPaidRowV2({super.key, required this.checkbox, required this.label, required this.sub, required this.price});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final priceW = resLineWidth(context, price.data ?? '', price.style ?? const TextStyle());
        final rest = c.maxWidth - 30 - 8 - priceW;
        final inline = resWordsFit(context, label.data ?? '', label.style ?? const TextStyle(), rest, minScale: 0.85) &&
            resWordsFit(context, sub.data ?? '', sub.style ?? const TextStyle(), rest, minScale: 0.85);
        final texts = <Widget>[MgWordFit(child: label), MgWordFit(child: sub)];
        return Row(children: [
          checkbox,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...texts,
              if (!inline) ...[const SizedBox(height: 2), price],
            ]),
          ),
          if (inline) ...[const SizedBox(width: 8), price],
        ]);
      });
}
