import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../catalog_provider.dart';
import '../widgets/availability_calendar.dart';
import 'catalog_text.dart';

/// "Kdy jedeš?" light sheet of the v2 Motorky tab (PLAN §2.2.3): two weekend
/// presets, "Bez termínu" and the existing `AvailabilityCalendar` (its v2
/// look = uniform band). Every pick writes `catalogFilterProvider` EXACTLY
/// like the old search screen (`_onRangeSelected` / `onReset`): the list
/// filters by availability from the same provider.
Future<void> showCatalogDateSheet(BuildContext context) => showMgSheet<void>(
      context,
      title: t(context).tr('v2CatDateTitle'),
      builder: (_) => const _CatalogDateBody(),
      footer: Builder(
        builder: (ctx) => MgBtnInk(
          label: t(ctx).tr('v2CatDone'),
          onTap: () => Navigator.of(ctx).maybePop(),
        ),
      ),
    );

/// Same write as the old `_onRangeSelected`.
void catSetDates(WidgetRef ref, DateTime start, DateTime end) {
  final filter = ref.read(catalogFilterProvider);
  ref.read(catalogFilterProvider.notifier).state = filter.copyWith(
    startDate: () => start,
    endDate: () => end,
  );
}

/// Same write as the old calendar `onReset`.
void catClearDates(WidgetRef ref) {
  final filter = ref.read(catalogFilterProvider);
  ref.read(catalogFilterProvider.notifier).state = filter.copyWith(
    startDate: () => null,
    endDate: () => null,
  );
}

class _CatalogDateBody extends ConsumerWidget {
  const _CatalogDateBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final f = ref.watch(catalogFilterProvider);
    final now = DateTime.now();
    final w1 = catWeekend(now);
    final w2 = catWeekend(now, skip: 1);
    bool isRange((DateTime, DateTime) r) =>
        f.startDate != null && f.endDate != null && tripSameDay(f.startDate!, r.$1) && tripSameDay(f.endDate!, r.$2);
    Widget preset(String label, (DateTime, DateTime) r) => MgChoiceChip(
          label: label,
          sub: catRange(tr, r.$1, r.$2),
          selected: isRange(r),
          icon: MgIcons.calendarCheck,
          onTap: () => catSetDates(ref, r.$1, r.$2),
        );
    final hasDates = f.startDate != null && f.endDate != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        preset(tr.tr('v2CatPresetWeekend'), w1),
        preset(tr.tr('v2CatPresetNextWeekend'), w2),
        MgChoiceChip(
          label: tr.tr('v2CatPresetNone'),
          sub: tr.tr('v2CatPresetNoneSub'),
          selected: !hasDates,
          onTap: () => catClearDates(ref),
        ),
      ]),
      const SizedBox(height: 16),
      if (hasDates) ...[
        TripSummaryRow(start: f.startDate!, end: f.endDate, days: catDayCount(f.startDate!, f.endDate!)),
        const SizedBox(height: 12),
      ],
      Text(tr.tr('v2CatSingleDayHint'), style: MgType.small.copyWith(color: MgColors.lead)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MgColors.line),
        ),
        child: AvailabilityCalendar(
          onRangeSelected: (s, e) => catSetDates(ref, s, e),
          onReset: () => catClearDates(ref),
          selectedStart: f.startDate,
          selectedEnd: f.endDate,
        ),
      ),
    ]);
  }
}
