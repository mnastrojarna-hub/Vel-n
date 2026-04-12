import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../booking_models.dart';
import 'booking_section_wrapper.dart';

/// Section 3 – Čas vyzvednutí (pickup time selector).
Widget bookingTimeSection({
  required BookingDraft draft,
  required void Function(String) onTimeSelected,
}) {
  const times = [
    '07:00', '08:00', '09:00', '10:00', '11:00', '12:00',
    '13:00', '14:00', '15:00', '16:00', '17:00', '18:00',
  ];

  return bookingSecWrapper(
    3,
    'ČAS VYZVEDNUTÍ',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vyberte čas vyzvednutí / přistavení',
          style: TextStyle(fontSize: 11, color: MotoGoColors.g400),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: times.map((t) {
            final active = draft.pickupTime == t;
            return GestureDetector(
              onTap: () => onTimeSelected(t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? MotoGoColors.greenDarker
                      : MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        active ? FontWeight.w900 : FontWeight.w600,
                    color: active ? Colors.white : MotoGoColors.greenDarker,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );
}
