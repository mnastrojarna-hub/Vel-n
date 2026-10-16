import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/calendar/trip_day_state.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../booking/booking_models.dart';
import '../../moto_model.dart';
import '../catalog_text.dart';

/// White receipt of the calculator (board `.rc`): dates + days chip, one bar
/// per day (≤ 31, labels ≤ 10 days), rows grouped by day price, the ½ row,
/// the loyalty row and the total — every number from the given
/// `PriceBreakdown` (`quoteFor`, same as `/booking`) and the bike's day
/// prices. Display only.
class CalcReceiptV2 extends StatelessWidget {
  final Motorcycle moto;
  final DateTime start;
  final DateTime end;
  final PriceBreakdown q;

  const CalcReceiptV2({super.key, required this.moto, required this.start, required this.end, required this.q});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final prices = moto.prices!;
    final days = <DateTime>[];
    for (var d = DateTime(start.year, start.month, start.day);
        !d.isAfter(DateTime(end.year, end.month, end.day));
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
    // Rows grouped by day price (same order as the days).
    final groups = <double, List<DateTime>>{};
    for (final d in days) {
      groups.putIfAbsent(prices.forWeekday(d.weekday), () => []).add(d);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.receipt,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(tr.tr('v2YourPrice').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.link)),
          ),
          MgBump(
            trigger: days.length,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
              child: Text(catDays(tr, days.length), style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDark))),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(text: '${tr.tr('v2CalPickup')} ', style: MgType.small.copyWith(color: MgColors.lead)),
          TextSpan(text: tripShortDate(tr, start), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
          TextSpan(text: '  →  ${tr.tr('v2CalReturn')} ', style: MgType.small.copyWith(color: MgColors.lead)),
          TextSpan(text: tripShortDate(tr, end), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
        ])),
        if (days.length <= 31) ...[
          const SizedBox(height: 14),
          Text(tr.tr('v2CalcChart'), style: MgType.meta.copyWith(color: MgColors.meta)),
          const SizedBox(height: 6),
          CalcBars(
            values: [for (final d in days) prices.forWeekday(d.weekday)],
            labels: days.length <= 10 ? [for (final d in days) tr.tr('v2CalWdAbbr${d.weekday}')] : null,
            weekend: [for (final d in days) d.weekday >= 6],
            halfFirst: q.latePickupDiscount > 0,
          ),
        ],
        const SizedBox(height: 12),
        for (final g in groups.entries)
          _row(
            g.value.length == 1
                ? '${tripShortDate(tr, g.value.first)} · ${catMoney(g.key)}'
                : '${g.value.length} × ${catMoney(g.key)}',
            catMoney(g.key * g.value.length),
          ),
        const Divider(height: 16, color: MgColors.line),
        _row(tr.trArgs('v2DetBreakRent', {'days': catDays(tr, q.days)}), catMoney(q.basePrice), strong: true),
        if (q.latePickupDiscount > 0) _row(tr.tr('v2CalcLateRow'), '−${catMoney(q.latePickupDiscount)}', minus: true),
        if (q.loyaltyDiscount > 0)
          _row(
            tr.trArgs('v2DetBreakLoyalty', {'rank': q.loyaltyRankName ?? '', 'pct': q.loyaltyPercent}),
            '−${catMoney(q.loyaltyDiscount)}',
            minus: true,
          ),
        const Divider(height: 16, color: MgColors.line),
        _row(tr.tr('v2YourPrice'), catMoney(q.total), total: true),
        const SizedBox(height: 8),
        Text(tr.tr('v2CalcVat'), style: MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.meta)),
        const SizedBox(height: 2),
        Text(tr.tr('pricingNote'), style: MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.meta)),
      ]),
    );
  }

  Widget _row(String l, String v, {bool strong = false, bool minus = false, bool total = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(l,
                style: (total ? MgType.title : MgType.small).copyWith(
                    fontWeight: strong || total ? FontWeight.w800 : FontWeight.w600,
                    color: total ? MgColors.ink : MgColors.body2)),
          ),
          const SizedBox(width: 8),
          Text(v,
              style: MgType.tab((total ? MgType.title : MgType.small).copyWith(
                  fontWeight: FontWeight.w800, color: minus || total ? MgColors.price : MgColors.ink))),
        ]),
      );
}

/// Per-day bars (`gBar`; weekend bars darker). [halfFirst] = the first day
/// at half height with a "½" tag (pickup from 12:00).
class CalcBars extends StatelessWidget {
  final List<double> values;
  final List<String>? labels;
  final List<bool> weekend;
  final bool halfFirst;
  const CalcBars({super.key, required this.values, required this.weekend, this.labels, this.halfFirst = false});

  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    return ExcludeSemantics(
      child: SizedBox(
        height: labels == null ? 64 : 80,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: values.length > 14 ? 1 : 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (i == 0 && halfFirst) Text('½', style: MgType.micro.copyWith(color: MgColors.link)),
                  MgProgressOnce(
                    duration: const Duration(milliseconds: 500),
                    delay: Duration(milliseconds: 45 * (i < 10 ? i : 10)),
                    builder: (_, t) => Container(
                      height: (max <= 0 ? 0 : 52 * values[i] / max) * (i == 0 && halfFirst ? 0.5 : 1) * t + 2,
                      decoration: BoxDecoration(
                        gradient: weekend[i] ? MgGradients.barWeekend : MgGradients.bar,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  if (labels != null) ...[
                    const SizedBox(height: 4),
                    Text(labels![i], maxLines: 1, style: MgType.micro.copyWith(color: MgColors.meta, fontSize: 10)),
                  ],
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
