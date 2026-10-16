import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../moto_model.dart';

/// Up to 4 key spec tiles (board `.sg4`): value 17/800 ink + unit + label
/// from the bike's existing fields (power, engine, weight, seat height,
/// torque, tank — first four present). Labels = the old spec keys.
class DetailKeyTilesV2 extends StatelessWidget {
  final Motorcycle moto;
  const DetailKeyTilesV2({super.key, required this.moto});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final m = moto;
    String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    final tiles = <(String, String, String, String)>[
      if (m.powerKw != null) (MgIcons.gauge, n(m.powerKw!), 'kW', tr.tr('specPower')),
      if (m.engineCc != null) (MgIcons.moto, n(m.engineCc!), 'ccm', tr.tr('specEngine')),
      if (m.weightKg != null) (MgIcons.scale, n(m.weightKg!), 'kg', tr.tr('specWeight')),
      if (m.seatHeightMm != null && m.seatHeightMm! > 0) (MgIcons.ruler, n(m.seatHeightMm!), 'mm', tr.tr('specSeatHeight')),
      if (m.torqueNm != null) (MgIcons.speed, n(m.torqueNm!), 'Nm', tr.tr('specTorque')),
      if (m.fuelTankL != null) (MgIcons.fuel, n(m.fuelTankL!), 'l', tr.tr('specFuelTank')),
    ].take(4).toList();
    if (tiles.isEmpty) return const SizedBox.shrink();
    Widget tile(int i) => MgReveal(
          index: i,
          child: Semantics(
            container: true,
            label: '${tiles[i].$4}: ${tiles[i].$2} ${tiles[i].$3}',
            excludeSemantics: true,
            child: Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: BoxDecoration(
                color: MgColors.well,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MgColors.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: MgColors.panel, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: MgIcon(tiles[i].$1, size: 16, color: MgColors.neon)),
                  ),
                  const Spacer(),
                  Text(tiles[i].$3, style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.meta)),
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(tiles[i].$2, style: MgType.tab(MgType.section.copyWith(color: MgColors.ink, height: 1.1))),
                ),
                const SizedBox(height: 2),
                Text(tiles[i].$4, style: MgType.micro.copyWith(color: MgColors.meta)),
              ]),
            ),
          ),
        );
    return LayoutBuilder(builder: (context, c) {
      // 4 in a row only when every label word fits a tile (never a word
      // broken in half — "Hmotnost", "Потужність"); otherwise 2 × 2.
      final inner = (c.maxWidth - 24) / 4 - 16;
      final base = DefaultTextStyle.of(context).style.merge(MgType.micro);
      var fits = true;
      for (final tl in tiles) {
        for (final w in tl.$4.split(RegExp(r'\s+'))) {
          final tp = TextPainter(
            text: TextSpan(text: w, style: base),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          if (tp.width > inner) fits = false;
          tp.dispose();
        }
      }
      final cols = fits ? 4 : 2;
      final rows = <Widget>[];
      for (var r = 0; r * cols < 4 && r * cols < tiles.length; r++) {
        if (r > 0) rows.add(const SizedBox(height: 8));
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < cols; k++) ...[
              if (k > 0) const SizedBox(width: 8),
              Expanded(child: r * cols + k < tiles.length ? tile(r * cols + k) : const SizedBox.shrink()),
            ],
          ]),
        ));
      }
      return Column(children: rows);
    });
  }
}

/// "Všechny parametry" — the old `SpecsSection` data (`moto.specList`) as
/// a 2-column grid of well tiles (label caps + value), light.
class DetailAllParamsV2 extends StatelessWidget {
  final List<MapEntry<String, String>> specs;
  const DetailAllParamsV2({super.key, required this.specs});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in specs)
            Container(
              width: w,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MgColors.well,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MgColors.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.key.toUpperCase(), style: MgType.micro.copyWith(color: MgColors.meta, letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(s.value, style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
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
