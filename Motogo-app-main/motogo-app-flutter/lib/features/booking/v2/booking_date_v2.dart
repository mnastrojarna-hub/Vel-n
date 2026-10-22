import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/state_views.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/widgets/availability_calendar.dart';
import 'booking_v2_parts.dart';

/// "Termín" card of the v2 form — the old `_buildDateSection` content:
/// collapsed summary (range + days + Změnit → the form's `_openCalendar`)
/// or the hint + `AvailabilityCalendar` (its own v2 look) fed by the
/// form's booked-dates watch; a failed load shows the same `MgErrorView`
/// with the same retry. "Celkem za pronájem" = the rental base price.
class BookingDateCardV2 extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final bool hasDates;
  final int dayCount;
  final double basePrice;
  final bool calOpen;

  /// The form's booked-dates watch (null when no bike id).
  final AsyncValue<List<BookedDateRange>>? booked;
  final VoidCallback onOpenCalendar;
  final void Function(DateTime, DateTime) onRangeSelected;
  final VoidCallback onReset;
  final VoidCallback onRetryBooked;

  const BookingDateCardV2({
    super.key,
    required this.start,
    required this.end,
    required this.hasDates,
    required this.dayCount,
    required this.basePrice,
    required this.calOpen,
    required this.booked,
    required this.onOpenCalendar,
    required this.onRangeSelected,
    required this.onReset,
    required this.onRetryBooked,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final b = booked;
    final showCal = calOpen || !hasDates;
    return BkCard(
      icon: MgIcons.calendarCheck,
      title: tr.tr('v2BkDatesTitle'),
      trailing: hasDates ? BkDaysChip(dayCount) : null,
      child: bkAnimatedSize(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!showCal) _summary(context),
          if (showCal) ...[
            Text(tr.tr('v2BkSingleDayHint'), style: MgType.small.copyWith(color: MgColors.lead)),
            const SizedBox(height: 10),
            if (b != null && b.hasError && !b.hasValue)
              // Obsazenost se nenačetla — stejná hláška a oprava jako dřív.
              MgErrorView(
                error: b.error,
                what: tr.tr('fxBookedDatesFail'),
                onRetry: onRetryBooked,
                compact: true,
                contact: false,
              )
            else ...[
              if (b != null && b.isLoading && !b.hasValue)
                const Padding(padding: EdgeInsets.only(bottom: 8), child: TripAvailabilityBanner(loading: true)),
              AvailabilityCalendar(
                bookedDates: b?.valueOrNull ?? [],
                selectedStart: start,
                selectedEnd: end,
                onRangeSelected: onRangeSelected,
                onReset: onReset,
              ),
            ],
          ],
          if (hasDates) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: MgColors.well,
                borderRadius: BorderRadius.circular(MgRadius.action),
                border: Border.all(color: MgColors.line),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(tr.tr('totalForRental'),
                      style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead)),
                ),
                MgBump(
                  trigger: basePrice,
                  child: Text(bkMoney(basePrice),
                      style: MgType.tab(MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.price))),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final tr = t(context);
    final range = bkRange(tr, start!, end!);
    return Semantics(
      button: true,
      label: tr.trArgs('v2BkChangeDatesA11y', {'range': range}),
      excludeSemantics: true,
      onTap: onOpenCalendar,
      child: MgPress(
        onTap: onOpenCalendar,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(MgRadius.button),
            border: Border.all(color: MgColors.lineInput, width: 1.5),
          ),
          child: Row(children: [
            MgIcon(MgIcons.calendarCheck, size: 20, color: MgColors.link),
            const SizedBox(width: 10),
            Expanded(
              // Each date stays whole ("23/10" never splits at the slash);
              // a date wider than the column shrinks a little instead.
              child: MgWordFit(
                child: Text(range.replaceAll('/', '/\u2060'),
                    style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
              ),
            ),
            const SizedBox(width: 8),
            MgIcon(MgIcons.edit, size: 16, color: MgColors.link),
            const SizedBox(width: 4),
            Text(tr.tr('v2BkChange'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
          ]),
        ),
      ),
    );
  }
}
