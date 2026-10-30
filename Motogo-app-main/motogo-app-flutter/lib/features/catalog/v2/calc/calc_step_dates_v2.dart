import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/calendar/trip_calendar.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../catalog_provider.dart';
import '../../moto_model.dart';
import '../../widgets/availability_calendar.dart';
import '../../widgets/validation_banner.dart';
import '../catalog_price.dart' show catAnimatedSize;
import '../catalog_text.dart';
import 'calc_parts_v2.dart';
import 'calc_state.dart';

/// Step ③ of the calculator: the existing `AvailabilityCalendar` (same
/// selection rules as the detail: busy days not selectable, a range over a
/// busy day refused, single day = same day twice) fed with the bike's
/// `bookedDatesProvider` — while it loads / fails the banner says so and
/// the CTA stays disabled (never "all free"). Validation (ŘP, overlap with
/// your bookings, min / max days) = the existing `ValidationBanner`.
///
/// A given range (picked here, carried from the list / Home / a detail)
/// folds into its summary + "Změnit" like the detail's date step (owner
/// 2026-10-22: nothing already given is asked again); a range over a busy
/// day stays open — it has to change.
class CalcStepDatesV2 extends ConsumerStatefulWidget {
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
  ConsumerState<CalcStepDatesV2> createState() => _CalcStepDatesV2State();
}

class _CalcStepDatesV2State extends ConsumerState<CalcStepDatesV2> {
  /// "Změnit" tapped: the calendar stays open until a new range is picked.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final st = widget.st;
    final moto = widget.moto;
    final n = ref.read(calcStateProvider.notifier);
    final b = widget.booked;
    final loading = b != null && b.isLoading && !b.hasValue;
    final failed = b != null && b.hasError && !b.isLoading;
    final folded = st.hasRange && !_open && !widget.busyInRange;
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
          onRetry: moto == null ? null : () => ref.invalidate(bookedDatesProvider(moto.id)),
        ),
        const SizedBox(height: 10),
      ],
      catAnimatedSize(
        context,
        folded
            ? const SizedBox(width: double.infinity)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AvailabilityCalendar(
                  key: ValueKey('calc-cal-${moto?.id ?? 'any'}'),
                  dayPrices: moto?.prices,
                  bookedDates: b?.valueOrNull ?? const [],
                  selectedStart: st.start,
                  selectedEnd: st.end,
                  onRangeSelected: (s, e) {
                    setState(() => _open = false);
                    n.setRange(s, e);
                  },
                  onStartSelected: n.setStart,
                  onReset: n.clearDates,
                ),
                if (moto == null) ...[
                  const SizedBox(height: 10),
                  CalcHint(tr.tr('v2CalcCalAny')),
                ],
              ]),
      ),
      if (widget.busyInRange) ...[
        const SizedBox(height: 10),
        CalcHint(tr.tr('v2CalcRangeBusy'), warn: true),
      ],
      if (moto != null && st.hasRange) ValidationBanner(moto: moto, startDate: st.start!, endDate: st.end!),
      if (st.start != null)
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
          MgBtnText(
            label: tr.tr('v2CatDateClear'),
            color: MgColors.link,
            onTap: () {
              setState(() => _open = false);
              n.clearDates();
            },
          ),
          if (folded) MgBtnText(label: tr.tr('v2DetChange'), icon: MgIcons.edit, onTap: () => setState(() => _open = true)),
        ]),
    ]);
  }
}
