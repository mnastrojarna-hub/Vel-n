import 'package:flutter/material.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_ui_helpers.dart';
import 'i18n/i18n_provider.dart';

/// Time-of-pickup selector — tap to open native time picker.
class BookingFormTimeSection extends StatelessWidget {
  const BookingFormTimeSection({
    super.key,
    required this.draft,
    required this.onTimeChanged,
  });

  final BookingDraft draft;
  final void Function(String newTime) onTimeChanged;

  @override
  Widget build(BuildContext context) {
    final hasTime = draft.pickupTime != null;
    final label = hasTime ? draft.pickupTime! : '09:00';

    return bookingCard(
      3,
      t(context).tr('pickupTimeLabel'),
      GestureDetector(
        onTap: () async {
          final parts = label.split(':');
          final initial = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
          final picked = await showTimePicker(
            context: context,
            initialTime: initial,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                alwaysUse24HourFormat: true,
              ),
              child: Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF1A8A18),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Color(0xFF0F1A14),
                  ),
                ),
                child: child!,
              ),
            ),
          );
          if (picked != null) {
            final hh = picked.hour.toString().padLeft(2, '0');
            final mm = picked.minute.toString().padLeft(2, '0');
            onTimeChanged('$hh:$mm');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8FFE8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF74FB71), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 18,
                  color: Color(0xFF1A8A18)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F1A14),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t(context).tr('hours'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8AAB99),
                  decoration: TextDecoration.none,
                ),
              ),
              const Spacer(),
              const Text(
                'ZMĚNIT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3DBA3A),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
