import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/widgets/availability_calendar.dart';
import '../booking_models.dart';
import 'booking_section_wrapper.dart';

/// Section 2 – Datum (date/calendar selection with price summary).
Widget bookingDateSection({
  required BookingDraft draft,
  required bool hasDates,
  required int dc,
  required PriceBreakdown bd,
  required bool calOpen,
  required VoidCallback onOpenCal,
  required void Function(DateTime?, DateTime?) onRangeSelected,
  required VoidCallback onReset,
}) {
  String fmtDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

  return bookingSecWrapper(
    2,
    'DATUM',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!calOpen && hasDates)
          GestureDetector(
            onTap: onOpenCal,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: MotoGoColors.greenDarker),
                const SizedBox(width: 6),
                Text(
                  '${fmtDate(draft.startDate!)} – ${fmtDate(draft.endDate!)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenDarker,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$dc ${dc == 1 ? 'den' : dc < 5 ? 'dny' : 'dní'}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'UPRAVIT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.greenDark,
                  ),
                ),
              ]),
            ),
          ),
        if (calOpen || !hasDates) ...[
          const Text(
            'Pro výběr jednoho dne klikněte dvakrát',
            style: TextStyle(fontSize: 11, color: MotoGoColors.g400),
          ),
          const SizedBox(height: 8),
          Consumer(builder: (context, ref, _) {
            final booked =
                ref.watch(bookedDatesProvider(draft.motoId ?? ''));
            return AvailabilityCalendar(
              bookedDates: booked.valueOrNull ?? [],
              selectedStart: draft.startDate,
              selectedEnd: draft.endDate,
              onRangeSelected: (s, e) => onRangeSelected(s, e),
              onReset: onReset,
            );
          }),
        ],
        if (hasDates)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: MotoGoColors.green, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(children: [
                const Text(
                  'CELKOVÁ CENA ZA PRONÁJEM',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.g400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${bd.basePrice.toStringAsFixed(0)} Kč',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: MotoGoColors.greenDarker,
                  ),
                ),
                const Text(
                  'Cena bez DPH, nejsme plátci',
                  style: TextStyle(fontSize: 9, color: MotoGoColors.g400),
                ),
              ]),
            ),
          ),
      ],
    ),
  );
}
