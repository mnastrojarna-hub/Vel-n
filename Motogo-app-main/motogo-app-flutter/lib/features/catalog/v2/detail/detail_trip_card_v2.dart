import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/calendar/trip_calendar.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/rank/rank_copy.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_chips.dart';
import '../../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../../core/v2/widgets/mg_price.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../booking/booking_models.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../catalog_provider.dart';
import '../../moto_model.dart';
import '../../widgets/availability_calendar.dart';
import '../../widgets/validation_banner.dart';
import '../calc/calc_parts_v2.dart';
import '../catalog_text.dart';
import '../catalog_price.dart';
import 'detail_trip_parts_v2.dart';

/// "Tvoje jízda" card of the v2 detail (V22 §2.4: light step rows + the
/// one dark total box). ① Termín = the page's own date state and
/// `AvailabilityCalendar` callbacks (expand / collapse, range, start,
/// reset — all owned by `_MotoDetailPageState`), availability banner,
/// `ValidationBanner`, a busy warning for carried dates ([busy]); ②
/// Předání a výbava = info only (chosen in the booking form; "i" tile +
/// the 12:00 saving from [quote12]); total = [quote] (the booking form's
/// price for a fresh draft) with the old list total struck, no deposit,
/// breakdown.
class DetailTripCardV2 extends ConsumerStatefulWidget {
  final Motorcycle moto;
  final DateTime? selStart;
  final DateTime? selEnd;
  final bool hasDates;
  final int dayCount;

  /// The old `PriceFooter` total (list price, no rank) — struck when the
  /// rank price is lower.
  final double listTotal;
  final PriceBreakdown? quote;

  /// The same trip with pickup from 12:00 (2+ days) — information only.
  final PriceBreakdown? quote12;
  final bool busy;
  final bool calendarExpanded;
  final VoidCallback onToggleCalendar;
  final void Function(DateTime, DateTime) onRangeSelected;
  final void Function(DateTime) onStartSelected;
  final VoidCallback onReset;
  final AsyncValue<List<BookedDateRange>> bookedAsync;

  const DetailTripCardV2({
    super.key,
    required this.moto,
    required this.selStart,
    required this.selEnd,
    required this.hasDates,
    required this.dayCount,
    required this.listTotal,
    required this.quote,
    required this.calendarExpanded,
    required this.onToggleCalendar,
    required this.onRangeSelected,
    required this.onStartSelected,
    required this.onReset,
    required this.bookedAsync,
    this.quote12,
    this.busy = false,
  });

  @override
  ConsumerState<DetailTripCardV2> createState() => _DetailTripCardV2State();
}

class _DetailTripCardV2State extends ConsumerState<DetailTripCardV2> {
  bool _breakdown = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final w = widget;
    final loyaltyAsync = ref.watch(loyaltyStatusProvider);
    final loyalty = loyaltyAsync.valueOrNull;
    final b = w.bookedAsync;
    final q = w.quote;
    final pct = loyalty?.percent ?? 0;
    final from = catFromPerDay(w.moto, pct);
    final cheapest = w.moto.prices?.cheapest ?? 0;
    Widget tile(String label, DateTime? d) => Expanded(
          child: Semantics(
            button: true,
            label: '$label ${d == null ? tr.tr('v2DetPickDate') : tripShortDate(tr, d)}',
            excludeSemantics: true,
            onTap: w.onToggleCalendar,
            child: MgPress(
              onTap: w.onToggleCalendar,
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: w.calendarExpanded ? MgColors.link : MgColors.lineInput,
                    width: w.calendarExpanded ? 2 : 1.5,
                  ),
                ),
                // Caps eyebrow ("TERUGBRENGEN", "ПОВЕРНЕННЯ") stays on one
                // line and scales down; the value never splits a word.
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(label,
                        maxLines: 1,
                        style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.meta, letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 4),
                  MgWordFit(
                    minScale: 0.75,
                    fitLines: 1,
                    child: Text(d == null ? tr.tr('v2DetPickDate') : tripShortDate(tr, d),
                        style: MgType.tab(MgType.title.copyWith(color: d == null ? MgColors.link : MgColors.ink))),
                  ),
                ]),
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MgColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          MgEyebrowDark(tr.tr('v2DetTrip')),
          if (loyalty != null && loyalty.level >= 1)
            MgRankChip(onLight: true, label: RankCopy.chip(tr, RankCopy.name(tr, loyalty.level, loyalty.rankName), loyalty.percent)),
        ]),
        const SizedBox(height: 18),
        // ① Termín
        Row(children: [
          CalcStepBadge(n: 1, done: w.hasDates),
          const SizedBox(width: 10),
          Expanded(child: Text(tr.tr('v2DetStepDates'), style: MgType.section.copyWith(color: MgColors.ink))),
          if (w.hasDates)
            MgBump(
              trigger: w.dayCount,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
                child: Text(catDays(tr, w.dayCount), style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDark))),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          tile(tr.tr('dateTabsPickup'), w.selStart),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: MgIcon(MgIcons.arrowRight, size: 18, color: MgColors.link),
          ),
          tile(tr.tr('dateTabsReturn'), w.selEnd),
        ]),
        if (!w.calendarExpanded && w.hasDates)
          Align(
            alignment: Alignment.centerRight,
            child: MgBtnText(label: tr.tr('v2DetChange'), icon: MgIcons.edit, onTap: w.onToggleCalendar),
          ),
        catAnimatedSize(context, !w.calendarExpanded
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 12),
                  if (b.isLoading && !b.hasValue)
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: TripAvailabilityBanner(loading: true)),
                  if (b.hasError && !b.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TripAvailabilityBanner(
                        error: true,
                        onRetry: () => ref.invalidate(bookedDatesProvider(w.moto.id)),
                      ),
                    ),
                  Text(tr.tr('v2BkSingleDayHint'), style: MgType.small.copyWith(color: MgColors.lead)),
                  const SizedBox(height: 8),
                  AvailabilityCalendar(
                    dayPrices: w.moto.prices,
                    bookedDates: b.valueOrNull ?? [],
                    selectedStart: w.selStart,
                    selectedEnd: w.selEnd,
                    onRangeSelected: w.onRangeSelected,
                    onStartSelected: w.onStartSelected,
                    onReset: w.onReset,
                  ),
                ]),
        ),
        if (w.busy) ...[
          const SizedBox(height: 10),
          CalcHint(tr.tr('v2CalcRangeBusy'), warn: true),
        ],
        if (w.hasDates) ValidationBanner(moto: w.moto, startDate: w.selStart!, endDate: w.selEnd!),
        const SizedBox(height: 20),
        // ② Předání a výbava — vybírá se v rezervaci (beze změny chování).
        DetailHandoverInfoV2(quote: q, quote12: w.quote12),
        const SizedBox(height: 20),
        if (loyaltyAsync.hasError && !loyaltyAsync.isLoading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // The note gets the full row; "Zkusit znovu" sits under it (a
            // side button squeezed "Treuerabatt" into a broken word).
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: MgIcon(MgIcons.info, size: 16, color: MgColors.warn),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MgWordFit(child: Text(tr.tr('v2DetLoyaltyFail'), style: MgType.small.copyWith(color: MgColors.warn))),
                ),
              ]),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: MgBtnText(label: tr.tr('retry'), onTap: () => ref.invalidate(loyaltyStatusProvider)),
              ),
            ]),
          ),
        if (w.hasDates && q != null && q.total > 0)
          MgTotalBox(
            eyebrow: '${tr.tr('v2YourPrice')} · ${catDays(tr, w.dayCount)}',
            value: catMoney(q.total),
            sub: '${tr.trArgs('v2AvgPerDay', {'amount': catMoney((q.total / (w.dayCount < 1 ? 1 : w.dayCount)).roundToDouble())})}'
                ' · ${tr.tr('v2DetNoDeposit')}',
            trailing: w.listTotal > q.total
                ? Text(catMoney(w.listTotal),
                    style: MgType.tab(MgType.small.copyWith(
                        color: MgColors.onDarkMeta, decoration: TextDecoration.lineThrough, decorationColor: MgColors.onDarkMeta)))
                : null,
            savingsChip: q.loyaltyDiscount > 0
                ? MgMeaningChip(
                    label: tr.trArgs('v2RankSaves', {'amount': catMoney(q.loyaltyDiscount)}),
                    tone: MgTone.ok,
                    dark: true,
                  )
                : null,
            onBreakdown: () => setState(() => _breakdown = !_breakdown),
            breakdownOpen: _breakdown,
            breakdown: _Breakdown(q: q, days: w.dayCount),
          )
        else
          MgTotalBox(
            eyebrow: tr.tr('v2CatPriceFrom'),
            value: cheapest > 0 ? '${catMoney(from)}${tr.tr('pricePerDay')}' : '–',
            sub: tr.tr('v2DetNoDatesTotal'),
            trailing: pct > 0 && from < cheapest
                ? Text(catMoney(cheapest),
                    style: MgType.tab(MgType.small.copyWith(
                        color: MgColors.onDarkMeta, decoration: TextDecoration.lineThrough, decorationColor: MgColors.onDarkMeta)))
                : null,
          ),
      ]),
    );
  }
}

class _Breakdown extends StatelessWidget {
  final PriceBreakdown q;
  final int days;
  const _Breakdown({required this.q, required this.days});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget row(String l, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
              child: Text(l, style: MgType.small.copyWith(color: strong ? MgColors.onDark : MgColors.onDarkLead)),
            ),
            Text(v,
                style: MgType.tab(MgType.small.copyWith(
                    fontWeight: FontWeight.w800, color: strong ? MgColors.neon : MgColors.onDark))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Divider(height: 12, color: MgColors.white(0.12)),
      row(tr.trArgs('v2DetBreakRent', {'days': catDays(tr, days)}), catMoney(q.basePrice)),
      if (q.loyaltyDiscount > 0)
        row(tr.trArgs('v2DetBreakLoyalty', {'rank': q.loyaltyRankName ?? '', 'pct': q.loyaltyPercent}),
            '−${catMoney(q.loyaltyDiscount)}'),
      row(tr.tr('v2YourPrice'), catMoney(q.total), strong: true),
      const SizedBox(height: 6),
      Text(tr.tr('v2DetBreakNote'), style: MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.onDarkMeta)),
      const SizedBox(height: 2),
      Text(tr.tr('pricingNote'), style: MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.onDarkMeta)),
    ]);
  }
}

/// Section wrapper of the light detail sheet (`.sec` + `.h2s`).
class DetailSectionV2 extends StatelessWidget {
  final String title;
  final String icon;
  final Widget child;
  const DetailSectionV2({super.key, required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            MgIconTileDark(icon, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(header: true, child: Text(title, style: MgType.section.copyWith(color: MgColors.ink))),
            ),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

/// Plain light card used under the sections.
class DetailCardV2 extends StatelessWidget {
  final Widget child;
  const DetailCardV2({super.key, required this.child});

  @override
  Widget build(BuildContext context) => MgCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: child);
}
