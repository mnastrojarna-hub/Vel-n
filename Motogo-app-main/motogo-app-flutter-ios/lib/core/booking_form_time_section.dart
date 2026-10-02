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
///
/// Samoobslužná pobočka (výdej/vrácení 24/7 kódem, zadání 2026-10-01 večer):
/// čas VYZVEDNUTÍ se volí vždy (sleva 50 % na 1. den od 12:00; kiosk takovou
/// rezervaci vydá až od 12:00) — pod výběrem je pak nápověda samoobsluhy
/// ([selfService]) místo obecné. Čas VRÁCENÍ na pobočku se nevolí
/// ([showReturn] = false, 23:59 doplní formulář), zobrazí se jen u vrácení na
/// adresu. [showPickup] zůstává pro úplnost; bez obou částí se karta
/// nevykreslí vůbec (číslování ostatních karet se záměrně nemění).
class BookingFormTimeSection extends StatelessWidget {
  const BookingFormTimeSection({
    super.key,
    required this.draft,
    required this.onTimeChanged,
    required this.onReturnTimeChanged,
    this.showPickup = true,
    this.showReturn = true,
    this.selfService = false,
  });

  final BookingDraft draft;
  final void Function(String newTime) onTimeChanged;
  final void Function(String newTime) onReturnTimeChanged;
  final bool showPickup;
  final bool showReturn;

  /// Vyzvednutí NA samoobslužné pobočce → nápověda `ssPickupHint`.
  final bool selfService;

  @override
  Widget build(BuildContext context) {
    if (!showPickup && !showReturn) return const SizedBox.shrink();
    final pickupLabel = draft.pickupTime ?? '09:00';
    final returnLabel = draft.returnTime ?? '19:00';

    return bookingCard(
      3,
      t(context).tr(showPickup ? 'pickupTimeLabel' : 'returnTimeLabel'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPickup) ...[
            TimeDropdownField(
              value: pickupLabel,
              onChanged: onTimeChanged,
            ),
            const SizedBox(height: 6),
            // Hint: pozdní vyzvednutí = 50 % sleva na 1. den (>=12:00, >=2 dny);
            // samoobsluha navíc: vrácení bez času + výdej kiosku až od 12:00.
            Text(
              '🌗 ${t(context).tr(selfService ? 'ssPickupHint' : 'latePickupHint12')}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A6357),
                decoration: TextDecoration.none,
              ),
            ),
          ],
          if (showPickup && showReturn) ...[
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
          ],
          if (showReturn)
            TimeDropdownField(
              value: returnLabel,
              onChanged: onReturnTimeChanged,
            ),
        ],
      ),
    );
  }
}
