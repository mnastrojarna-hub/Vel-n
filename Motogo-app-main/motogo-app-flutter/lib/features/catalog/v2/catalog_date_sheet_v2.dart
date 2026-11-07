import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../catalog_provider.dart';
import '../widgets/availability_calendar.dart';
import 'catalog_fit.dart';
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
      footer: const _CatalogDateFooter(),
    );

/// Board footer (CB-19): "POUŽÍT TERMÍN · 3 DNY" (neon on ink) with a
/// range, "Hotovo" without; "Zrušit termín" = the sheet's own clear.
class _CatalogDateFooter extends ConsumerWidget {
  const _CatalogDateFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final f = ref.watch(catalogFilterProvider);
    final s = f.startDate, e = f.endDate;
    final range = s != null && e != null;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MgBtnInk(
        label: range
            ? tr.trArgs('v2UxCbUseDates', {'days': catDays(tr, catDayCount(s, e))}).toUpperCase()
            : tr.tr('v2CatDone'),
        neonLabel: range,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      if (range) Center(child: MgBtnText(label: tr.tr('v2CatDateClear'), onTap: () => catClearDates(ref))),
    ]);
  }
}

/// Board "VYZVEDNUTÍ → VRÁCENÍ" well with the days chip (bumps on change).
class _RangeWell extends StatelessWidget {
  final DateTime start;
  final DateTime? end;
  const _RangeWell({required this.start, this.end});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget tile(String label, DateTime? d) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgWordFit(minScale: 0.8, child: Text(label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta))),
            const SizedBox(height: 2),
            Text(d == null ? '–' : tripShortDate(tr, d).replaceAll(' ', '\u00A0'),
                style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
          ]),
        );
    final days = end == null
        ? null
        : MgBump(
            trigger: catDayCount(start, end!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
              child: Text(catDays(tr, catDayCount(start, end!)).replaceAll(' ', '\u00A0'),
                  style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.neon))),
            ),
          );
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(MgRadius.button),
          border: Border.all(color: MgColors.line),
        ),
        child: LayoutBuilder(builder: (context, c) {
          // The days chip stays in the row while both caps labels keep
          // their longest word whole beside it; else it goes under them.
          final base = DefaultTextStyle.of(context).style.merge(MgType.eyebrow);
          final word = [tr.tr('dateTabsPickup'), tr.tr('dateTabsReturn')]
              .map((l) => catWordWidth(context, l.toUpperCase(), base))
              .reduce((a, b) => a > b ? a : b);
          final chipW = days == null ? 0.0 : catLineWidth(context, catDays(tr, catDayCount(start, end!)), base) + 30;
          final side = days == null || (c.maxWidth - 30 - chipW) / 2 >= word * 0.8;
          final row = Row(children: [
            tile(tr.tr('dateTabsPickup'), start),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: MgIcon(MgIcons.arrowRight, size: 18, color: MgColors.link),
            ),
            tile(tr.tr('dateTabsReturn'), end),
            if (side && days != null) ...[const SizedBox(width: 6), days],
          ]);
          if (side) return row;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            row,
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerStart, child: days),
          ]);
        }),
      ),
    );
  }
}

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
      // CB-19: the board's pickup → return well with the days chip.
      if (hasDates) ...[
        _RangeWell(start: f.startDate!, end: f.endDate),
        const SizedBox(height: 12),
      ],
      Text(tr.tr('v2BkSingleDayHint'), style: MgType.small.copyWith(color: MgColors.lead)),
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
