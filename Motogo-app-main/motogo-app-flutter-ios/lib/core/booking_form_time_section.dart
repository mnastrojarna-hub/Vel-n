import 'package:flutter/material.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_ui_helpers.dart';
import 'i18n/i18n_provider.dart';
import 'widgets/time_dropdown_field.dart';

/// Time section — pickup time + estimated return time. Hodina a minuta se volí
/// dvěma rozbalovacími nabídkami (stejné UI jako nastavení platnosti ŘP / datum
/// narození) místo nativního hodinového „showTimePicker". Return time is
/// mandatory (mirrors the web), so it is shown right under the pickup time.
/// There is intentionally only ONE time per direction here — when the customer
/// chooses delivery (přistavení) no extra / duplicate time field is added; this
/// pickup time doubles as the delivery time.
class BookingFormTimeSection extends StatelessWidget {
  const BookingFormTimeSection({
    super.key,
    required this.draft,
    required this.onTimeChanged,
    required this.onReturnTimeChanged,
  });

  final BookingDraft draft;
  final void Function(String newTime) onTimeChanged;
  final void Function(String newTime) onReturnTimeChanged;

  @override
  Widget build(BuildContext context) {
    final pickupLabel = draft.pickupTime ?? '09:00';
    final returnLabel = draft.returnTime ?? '19:00';

    return bookingCard(
      3,
      t(context).tr('pickupTimeLabel'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TimeDropdownField(
            value: pickupLabel,
            onChanged: onTimeChanged,
          ),
          const SizedBox(height: 6),
          // Hint: pozdní vyzvednutí = 50 % sleva na 1. den (>=12:00, >=2 dny)
          Text(
            '🌗 ${t(context).tr('latePickupHint12')}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A6357),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t(context).tr('returnTimeLabel'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A6357),
              letterSpacing: 0.5,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 6),
          TimeDropdownField(
            value: returnLabel,
            onChanged: onReturnTimeChanged,
          ),
        ],
      ),
    );
  }
}
