import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/calendar/trip_calendar.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../catalog_provider.dart';
import '../../moto_model.dart';
import '../../widgets/availability_calendar.dart';
import '../../widgets/validation_banner.dart';
import '../catalog_text.dart';
import 'calc_parts_v2.dart';
import 'calc_state.dart';

/// Step ③ of the calculator: the existing `AvailabilityCalendar` (same
/// selection rules as the detail: busy days not selectable, a range over a
/// busy day refused, single day = same day twice) fed with the bike's
/// `bookedDatesProvider` — while it loads / fails the banner says so and
/// the CTA stays disabled (never "all free"). Validation (ŘP, overlap with
/// your bookings, min / max days) = the existing `ValidationBanner`.
class CalcStepDatesV2 extends ConsumerWidget {
  final Motorcycle? moto;
  final CalcState st;
  final AsyncValue<List<BookedDateRange>>? booked;
  final bool busyInRange;

  const CalcStepDatesV2({
    super.key,
    required this.moto,
    required this.st,
    required this.booked,
    required this.busyInRange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final n = ref.read(calcStateProvider.notifier);
    final b = booked;
    final loading = b != null && b.isLoading && !b.hasValue;
    final failed = b != null && b.hasError && !b.isLoading;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (st.start != null) ...[
        TripSummaryRow(
          start: st.start!,
          end: st.end,
          days: st.hasRange ? catDayCount(st.start!, st.end!) : null,
        ),
        const SizedBox(height: 10),
      ],
      if (loading || failed) ...[
        TripAvailabilityBanner(
          loading: loading,
          error: failed,
          onRetry: moto == null ? null : () => ref.invalidate(bookedDatesProvider(moto!.id)),
        ),
        const SizedBox(height: 10),
      ],
      AvailabilityCalendar(
        key: ValueKey('calc-cal-${moto?.id ?? 'any'}'),
        bookedDates: b?.valueOrNull ?? const [],
        selectedStart: st.start,
        selectedEnd: st.end,
        onRangeSelected: n.setRange,
        onStartSelected: n.setStart,
        onReset: n.clearDates,
      ),
      if (moto == null) ...[
        const SizedBox(height: 10),
        CalcHint(tr.tr('v2CalcCalAny')),
      ],
      if (busyInRange) ...[
        const SizedBox(height: 10),
        CalcHint(tr.tr('v2CalcRangeBusy'), warn: true),
      ],
      if (moto != null && st.hasRange) ValidationBanner(moto: moto!, startDate: st.start!, endDate: st.end!),
      if (st.start != null)
        Align(
          alignment: Alignment.centerLeft,
          child: MgBtnText(label: tr.tr('v2CatDateClear'), onTap: n.clearDates, color: MgColors.link),
        ),
    ]);
  }
}
