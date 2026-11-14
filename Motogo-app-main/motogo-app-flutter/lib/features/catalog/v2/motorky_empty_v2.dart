import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../home/v2/home_offer_provider.dart' show HomeClosure, homeClosuresProvider, homeNextFreeProvider;
import '../catalog_provider.dart';
import '../moto_model.dart';
import 'catalog_mode_sync.dart' show catBeforeToday;

/// Why the Motorky list is empty (5.0.1), worst cause first.
enum MotorkyEmptyReason {
  /// Real filters on (`filterCount` > 0): they hide every bike.
  filters,

  /// Dates given: every bike's branch is closed on some day of them.
  closed,

  /// Dates given: every bike is booked (or in service) then.
  booked,

  /// No dates, no filters (e.g. only a branch with no bike).
  none,
}

/// The reason for [f] over the fleet [all] (read only, the same data as
/// Domů: `branch_closures`). Closures unknown → "booked".
MotorkyEmptyReason motorkyEmptyReason(CatalogFilter f, List<Motorcycle> all, List<HomeClosure> closures) {
  if (f.filterCount > 0) return MotorkyEmptyReason.filters;
  final s = f.startDate, e = f.endDate;
  if (s == null || e == null || catBeforeToday(s)) return MotorkyEmptyReason.none;
  final bikes = f.apply(all.where((m) => m.branchIsOpen != false).toList());
  final closed = bikes.isNotEmpty &&
      bikes.every((m) =>
          m.branchId != null &&
          closures.any((c) => c.branchId == m.branchId && !c.from.isAfter(e) && !c.to.isBefore(s)));
  return closed ? MotorkyEmptyReason.closed : MotorkyEmptyReason.booked;
}

/// The earliest "next free day" of the bikes [f] lets through that falls
/// AFTER the chosen dates (a day inside them would not help); null = none.
DateTime? motorkyNextFree(CatalogFilter f, List<Motorcycle> all, Map<String, DateTime> next) {
  final e = f.endDate;
  if (e == null) return null;
  DateTime? best;
  for (final m in f.apply(all)) {
    final d = next[m.id];
    if (d != null && d.isAfter(e) && (best == null || d.isBefore(best))) best = d;
  }
  return best;
}

/// The empty Motorky list in the new look: a dark neon tile, the REASON as
/// the heading (filters / closed / booked out — the same words as Domů) and
/// the way out: "Zrušit filtry (n)" or "Vybrat jiný termín" (scrolls up to
/// the calendar). Informal texts.
class MotorkyEmptyV2 extends ConsumerWidget {
  final CatalogFilter filter;
  final VoidCallback onClearFilters;
  final VoidCallback onPickDates;
  const MotorkyEmptyV2({super.key, required this.filter, required this.onClearFilters, required this.onPickDates});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final all = ref.watch(motorcyclesProvider).valueOrNull ?? const <Motorcycle>[];
    final dated = filter.filterCount == 0 && filter.startDate != null && filter.endDate != null;
    final closures =
        dated ? ref.watch(homeClosuresProvider).valueOrNull ?? const <HomeClosure>[] : const <HomeClosure>[];
    final reason = motorkyEmptyReason(filter, all, closures);
    final next = reason == MotorkyEmptyReason.booked || reason == MotorkyEmptyReason.closed
        ? motorkyNextFree(filter, all, ref.watch(homeNextFreeProvider).valueOrNull ?? const {})
        : null;
    final (String title, List<String> lines, String? action, VoidCallback? onAction) = switch (reason) {
      MotorkyEmptyReason.filters => (
          tr.tr('motoFltNoneTitle'),
          [tr.tr('motoFltNoneText')],
          tr.trArgs('motoFltClearN', {'n': filter.filterCount}),
          onClearFilters,
        ),
      MotorkyEmptyReason.closed || MotorkyEmptyReason.booked => (
          tr.tr(reason == MotorkyEmptyReason.closed ? 'motoFltClosedTitle' : 'motoFltBookedTitle'),
          [
            if (next != null) tr.trArgs('motoFltFreeFrom', {'date': tripShortDate(tr, next)}),
            tr.tr('motoFltOtherDates'),
          ],
          tr.tr('motoFltPickDates'),
          onPickDates,
        ),
      MotorkyEmptyReason.none => (tr.tr('searchNoMotorcycles'), const <String>[], null, null),
    };
    return Padding(
      key: const ValueKey('motorky-empty'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: MgCard(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(children: [
          MgIconTileDark(reason == MotorkyEmptyReason.filters ? MgIcons.filter : MgIcons.moto, size: 64),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.ink)),
          for (final (i, l) in lines.indexed) ...[
            SizedBox(height: i == 0 ? 8 : 2),
            Text(l,
                textAlign: TextAlign.center,
                style: MgType.body.copyWith(
                    color: i == 0 && next != null ? MgColors.link : MgColors.body2,
                    fontWeight: i == 0 && next != null ? FontWeight.w800 : null)),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            MgBtnInk(key: const ValueKey('motorky-empty-action'), label: action, onTap: onAction, neonLabel: true),
          ],
        ]),
      ),
    );
  }
}
