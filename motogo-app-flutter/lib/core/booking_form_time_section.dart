import 'package:flutter/material.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_ui_helpers.dart';
import 'i18n/i18n_provider.dart';

/// Time-of-pickup selector section inside the booking form.
class BookingFormTimeSection extends StatelessWidget {
  const BookingFormTimeSection({
    super.key,
    required this.draft,
    required this.onTimeChanged,
  });

  final BookingDraft draft;

  /// Called with the new `HH:MM` string whenever the user changes time.
  final void Function(String newTime) onTimeChanged;

  @override
  Widget build(BuildContext context) {
    final curH = draft.pickupTime != null
        ? int.parse(draft.pickupTime!.split(':')[0])
        : 9;
    final curM = draft.pickupTime != null
        ? int.parse(draft.pickupTime!.split(':')[1])
        : 0;

    return bookingCard(
      3,
      t(context).tr('pickupTimeLabel'),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8FFE8),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: const Color(0xFF74FB71), width: 1.5),
            ),
            child: DropdownButton<int>(
              value: curH,
              underline: const SizedBox(),
              dropdownColor: Colors.white,
              iconEnabledColor: const Color(0xFF1A8A18),
              iconSize: 18,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F1A14),
              ),
              items: List.generate(
                24,
                (h) => DropdownMenuItem(
                  value: h,
                  child: Text(h.toString().padLeft(2, '0')),
                ),
              ),
              onChanged: (h) {
                if (h == null) return;
                final mm = curM.toString().padLeft(2, '0');
                onTimeChanged('${h.toString().padLeft(2, "0")}:$mm');
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              ':',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F1A14),
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8FFE8),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: const Color(0xFF74FB71), width: 1.5),
            ),
            child: DropdownButton<int>(
              value: curM,
              underline: const SizedBox(),
              dropdownColor: Colors.white,
              iconEnabledColor: const Color(0xFF1A8A18),
              iconSize: 18,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F1A14),
              ),
              items: [0, 15, 30, 45]
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.toString().padLeft(2, '0')),
                      ))
                  .toList(),
              onChanged: (m) {
                if (m == null) return;
                final hh = curH.toString().padLeft(2, '0');
                onTimeChanged('$hh:${m.toString().padLeft(2, "0")}');
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            t(context).tr('hours'),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8AAB99),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
