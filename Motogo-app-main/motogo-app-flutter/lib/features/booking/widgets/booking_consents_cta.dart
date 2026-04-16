import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../booking_models.dart';
import 'booking_section_wrapper.dart';

/// Consents section (VOP, GDPR, kids) for the booking form.
Widget bookingConsentsSection({
  required BookingDraft draft,
  required bool isKids,
  required void Function(bool) onConsentVop,
  required void Function(bool) onConsentGdpr,
  required void Function(bool) onConsentKids,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(children: [
      bookingCheckbox(
        'Souhlasím s obchodními podmínkami a VOP',
        draft.consentVop,
        onConsentVop,
      ),
      const SizedBox(height: 6),
      bookingCheckbox(
        'Souhlasím se zpracováním osobních údajů',
        draft.consentGdpr,
        onConsentGdpr,
      ),
      if (isKids) ...[
        const SizedBox(height: 6),
        bookingCheckbox(
          'Potvrzuji, že jsem zákonný zástupce a dětský '
          'motocykl bude pod mým dohledem',
          draft.consentKids,
          onConsentKids,
        ),
      ],
    ]),
  );
}

/// CTA button – continue to payment.
Widget bookingCtaButton({
  required BookingDraft draft,
  required bool isKids,
  required String? validationErr,
  required BuildContext context,
}) {
  final ok = draft.consentVop &&
      draft.consentGdpr &&
      (!isKids || draft.consentKids) &&
      draft.startDate != null &&
      draft.endDate != null &&
      draft.pickupTime != null &&
      validationErr == null;

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: ok ? () => context.push('/payment') : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: MotoGoColors.green,
          foregroundColor: Colors.black,
          disabledBackgroundColor: MotoGoColors.g200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'POKRAČOVAT K PLATBĚ',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ),
    ),
  );
}
