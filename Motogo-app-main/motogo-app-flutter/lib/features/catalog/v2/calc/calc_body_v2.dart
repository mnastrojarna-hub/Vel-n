import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_chips.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../booking/booking_entry.dart';
import '../../../booking/booking_quote.dart';
import '../../../booking/v2/booking_sync_v2.dart' show bookingRangeBusy;
import '../../../loyalty/loyalty_provider.dart';
import '../../../reservations/reservation_provider.dart' show reservationsProvider;
import '../../catalog_provider.dart';
import '../../moto_model.dart';
import '../catalog_date_sheet_v2.dart';
import '../catalog_mode.dart';
import '../catalog_text.dart';
import 'calc_free_list_v2.dart';
import 'calc_parts_v2.dart';
import 'calc_receipt_v2.dart';
import 'calc_state.dart';
import 'calc_step_dates_v2.dart';
import 'calc_step_moto_v2.dart';
import 'calc_sticky_v2.dart';
import 'calc_total_v2.dart';

/// The v2 price calculator — Motorky tab, mode "Spočítat cenu" (PLAN
/// §2.2.4, NEW, light steps + one dark total, V22 §2.4): ① pobočka,
/// ② motorka, ③ termín, ④ předání (info only), receipt + total.
/// Prices = `quoteFor` (the booking form's own calculation for a fresh
/// draft, standard pickup); the 12:00 half-day saving is information only
/// (owner 2026-10-22: no time choice before the form). REZERVOVAT =
/// `startBookingFromSelection` (PM-3) with the same bike and dates — the
/// pickup time is chosen in the booking form. While that REZERVOVAT is
/// enabled but scrolled away, the Motorky page shows it in a sticky dock
/// (`calc_sticky_v2.dart`, the same handler).
class CalcBodyV2 extends ConsumerStatefulWidget {
  const CalcBodyV2({super.key});

  @override
  ConsumerState<CalcBodyV2> createState() => _CalcBodyV2State();
}

class _CalcBodyV2State extends ConsumerState<CalcBodyV2> with CalcStickyTracker {
  final GlobalKey _datesKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    stickyAttach();
  }

  @override
  void dispose() {
    stickyDetach();
    super.dispose();
  }

  void _toDates() {
    final c = _datesKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), alignment: 0.1);
  }

  /// "Zobrazit volné motorky": the Motorky list with the same dates (and
  /// branch) — the same writes as the catalog date picker / branch chip.
  void _showFree(CalcState st) {
    catSetDates(ref, st.start!, st.end!);
    final f = ref.read(catalogFilterProvider);
    if (st.branchId != null) {
      ref.read(catalogFilterProvider.notifier).state = f.copyWith(branch: () => st.branchId);
    }
    ref.read(catalogModeProvider.notifier).state = CatalogMode.find;
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final st = ref.watch(calcStateProvider);
    final n = ref.read(calcStateProvider.notifier);
    final allAsync = ref.watch(motorcyclesProvider);
    if (!allAsync.hasValue) {
      stickyWant(null);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: allAsync.hasError
            ? MgErrorView(
                error: allAsync.error,
                what: tr.tr('fxMotosLoadFail'),
                onRetry: () => ref.invalidate(motorcyclesProvider),
              )
            : MgLoadingView(onRetry: () => ref.invalidate(motorcyclesProvider)),
      );
    }
    final all = allAsync.value!;
    final branches = ref.watch(branchesProvider);
    final offered = calcOffered(all, st.branchId);
    final openAll = calcOffered(all, null);
    Motorcycle? moto;
    for (final m in all) {
      if (m.id == st.motoId) moto = m;
    }
    final loyaltyAsync = ref.watch(loyaltyStatusProvider);
    final loyalty = loyaltyAsync.valueOrNull;
    final booked = moto == null ? null : ref.watch(bookedDatesProvider(moto.id));
    // The booking form's rule: the customer's own unpaid draft of this bike
    // is not a busy day (the payment replaces it); unknown data never blocks.
    final busyInRange = st.hasRange &&
        moto != null &&
        bookingRangeBusy(
          booked: booked?.valueOrNull,
          own: ref.watch(reservationsProvider).valueOrNull,
          motoId: moto.id,
          start: st.start,
          end: st.end,
        );

    int countIn(String? branch) => calcOffered(all, branch).length;
    String typeOf(String id) {
      for (final m in openAll) {
        if (m.branchId == id) return m.branchType == 'samoobslužná' ? tr.tr('v2CalcBranchSelf') : tr.tr('v2CalcBranchStaffed');
      }
      return '';
    }

    final hasPrices = moto != null && (moto.prices?.cheapest ?? 0) > 0;
    CalcStickyData? sticky;
    Widget result;
    if (moto == null && st.hasRange) {
      result = CalcFreeListV2(st: st, onShowAll: () => _showFree(st));
    } else if (moto != null && st.hasRange && hasPrices) {
      final q = quoteFor(moto, st.start!, st.end!, loyalty: loyalty);
      final q12 = quoteFor(moto, st.start!, st.end!, pickupTime: '12:00', loyalty: loyalty);
      final loading = booked != null && !booked.hasValue && !booked.hasError;
      final failed = booked != null && booked.hasError;
      final blocked = loading
          ? tr.tr('v2CalLoading')
          : failed
              ? tr.tr('v2CalError')
              : busyInRange
                  ? tr.tr('v2CalcRangeBusy')
                  : null;
      final m = moto;
      void book() => startBookingFromSelection(context, ref, m, st.start!, st.end!);
      if (blocked == null) sticky = CalcStickyData(moto: m, start: st.start!, end: st.end!, total: q.total, onBook: book);
      result = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgEnter(trigger: '${m.id}${st.start}${st.end}', child: CalcReceiptV2(moto: m, start: st.start!, end: st.end!, q: q)),
        const SizedBox(height: 12),
        CalcTotalV2(
          q: q,
          q12: q12,
          rankName: q.loyaltyRankName,
          loyaltyFailed: loyaltyAsync.hasError,
          onRetryLoyalty: () => ref.invalidate(loyaltyStatusProvider),
          blockedReason: blocked,
          ctaKey: stickyCtaKey,
          onBook: blocked != null ? null : book,
        ),
      ]);
    } else if (moto != null && st.start == null && hasPrices) {
      final p = moto.prices!;
      result = MgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr.tr('v2CalcChart'), style: MgType.section.copyWith(color: MgColors.ink)),
          const SizedBox(height: 8),
          CalcBars(
            values: p.asList,
            labels: [for (var i = 1; i <= 7; i++) tr.tr('v2CalWdAbbr$i')],
            weekend: const [false, false, false, false, false, true, true],
          ),
          const SizedBox(height: 10),
          CalcFromPrice(moto: moto, pct: loyalty?.percent ?? 0),
          const SizedBox(height: 6),
          Text(tr.tr('v2CalcSumDates'), style: MgType.body.copyWith(color: MgColors.body2)),
          const SizedBox(height: 12),
          MgBtnGhostLight(label: tr.tr('v2CalcPickDatesCta'), icon: MgIcons.calendarCheck, onTap: _toDates),
        ]),
      );
    } else {
      result = CalcHint(tr.tr(st.start != null && st.end == null ? 'v2CalcSumPickEnd' : 'v2CalcSumEmpty'));
    }
    stickyWant(sticky);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CalcHeadCardV2(),
        const SizedBox(height: 12),
        CalcStepCardV2(
          n: 1,
          done: true,
          title: tr.tr('v2CalcStepBranch'),
          // Choice chips (wrap) — a 3-way segmented control broke words of
          // the long branch / type names in de, fr, uk.
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            MgChoiceChip(
              label: tr.tr('v2CalcBranchAll'),
              sub: catCount(tr, countIn(null)),
              selected: st.branchId == null,
              onTap: () => n.setBranch(null, currentMoto: moto),
            ),
            for (final b in branches)
              MgChoiceChip(
                label: b['name'] as String,
                sub: typeOf(b['id'] as String),
                icon: MgIcons.pin,
                selected: st.branchId == b['id'],
                onTap: () => n.setBranch(b['id'] as String, currentMoto: moto),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        CalcStepCardV2(
          n: 2,
          done: moto != null,
          title: tr.tr('v2CalcStepMoto'),
          child: CalcStepMotoV2(offered: offered, selected: moto),
        ),
        const SizedBox(height: 12),
        CalcStepCardV2(
          key: _datesKey,
          n: 3,
          done: st.hasRange,
          title: tr.tr('v2CalcStepDates'),
          child: CalcStepDatesV2(moto: moto, st: st, booked: booked, busyInRange: busyInRange),
        ),
        const SizedBox(height: 12),
        CalcStepCardV2(
          n: 4,
          // Info only (owner 2026-10-22): the pickup time — and with it the
          // 12:00 half-day saving — is chosen in the booking form; an "i"
          // tile, never a step that looks done or pending.
          info: true,
          title: tr.tr('v2CalcStepHandover'),
          child: CalcHint(tr.tr('v2LpCalcHandover')),
        ),
        const SizedBox(height: 16),
        result,
        const SizedBox(height: 14),
        if (moto == null || !moto.isTrailer)
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final k in const ['v2CalcIncl1', 'v2CalcIncl2', 'v2CalcIncl3'])
              MgMeaningChip(label: tr.tr(k), tone: MgTone.ok),
          ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          MgIcon(MgIcons.lock, size: 16, color: MgColors.lead),
          const SizedBox(width: 6),
          Flexible(
            child: Text(tr.tr('v2CalcAssure'),
                textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.lead)),
          ),
        ]),
      ]),
    );
  }
}
