import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../moto_model.dart';
import '../catalog_fit.dart';

/// "Všechny parametry" — the old `SpecsSection` data (`moto.specList`) as
/// a 2-column grid of well tiles (label caps + value), light.
class DetailAllParamsV2 extends StatelessWidget {
  final List<MapEntry<String, String>> specs;
  const DetailAllParamsV2({super.key, required this.specs});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        final base = DefaultTextStyle.of(context).style;
        final keyStyle = MgType.micro.copyWith(color: MgColors.meta, letterSpacing: 0.3);
        final valStyle = MgType.tab(MgType.title.copyWith(color: MgColors.ink));
        // A tile whose longest word (a caps label like "RIJBEWIJSCATEGORIE"
        // or a long value) does not fit half the width spans the full row —
        // never a word broken in half; MgWordFit is the last safety net.
        bool wide(MapEntry<String, String> s) =>
            catWordWidth(context, s.key.toUpperCase(), base.merge(keyStyle)) > w - 22 ||
            catWordWidth(context, s.value, base.merge(valStyle)) > w - 22;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in specs)
            Container(
              width: wide(s) ? c.maxWidth : w,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MgColors.well,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MgColors.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(minScale: 0.7, child: Text(s.key.toUpperCase(), style: keyStyle)),
                const SizedBox(height: 2),
                MgWordFit(minScale: 0.75, child: Text(s.value, style: valStyle)),
              ]),
            ),
        ]);
      });
}

/// "Ceník podle dne" — the old `PricingTable` data (list price per weekday
/// Po–Ne + the pricing note), light, weekend cells tinted.
class DetailPriceTableV2 extends StatelessWidget {
  final DayPrices prices;
  const DetailPriceTableV2({super.key, required this.prices});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: i >= 4 ? MgColors.weekendCell : MgColors.well,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MgColors.line),
              ),
              child: Column(children: [
                Text(tr.tr(DayPrices.dayLabelKeys[i]).toUpperCase(),
                    maxLines: 1, style: MgType.micro.copyWith(color: i >= 4 ? MgColors.link : MgColors.meta)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(prices.asList[i] > 0 ? prices.asList[i].toStringAsFixed(0) : '–',
                      style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
                ),
              ]),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Text(tr.tr('pricingCurrencyPerDay'), style: MgType.meta.copyWith(color: MgColors.meta)),
      const SizedBox(height: 4),
      Text(tr.tr('pricingNote'), style: MgType.small.copyWith(color: MgColors.lead)),
    ]);
  }
}
