import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import 'payment_provider.dart';

/// Potvrzení odchodu z běžící platby (šipka, systémové „zpět", záložka).
/// true = zákazník chce odejít. Platba může i tak doběhnout — výsledek najde
/// v Rezervacích / e-mailu; nikdy nesmí odejít bez vysvětlení.
Future<bool> confirmLeaveRunningPayment(BuildContext context) async {
  final tr = t(context);
  final leave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr.tr('psLeaveTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(tr.tr('psLeaveBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr.tr('psLeave'),
              style: const TextStyle(color: MotoGoColors.g500)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr.tr('psStay')),
        ),
      ],
    ),
  );
  return leave == true;
}

/// „Napsat nám" — zprávy v appce (odpověď přijde tamtéž), kontakt e-mailem a
/// telefonem je v patičce chybových hlášek.
void openContactUs(BuildContext context) {
  context.push(Routes.messages);
}

/// Výsledek „Platba se ověřuje" pro rezervaci (nová / dokončovaná / obnovená).
PaymentOutcome pendingBookingOutcome(
  AppTranslations tr, {
  required String bookingId,
  String? verifiedRoute,
}) =>
    PaymentOutcome(
      kind: PaymentOutcomeKind.pending,
      title: tr.tr('psPendingTitle'),
      subtitle: tr.tr('psPendingSub'),
      nextStepNote: tr.tr('psPendingBody'),
      ctaLabel: tr.tr('psMyReservations'),
      ctaRoute: Routes.reservations,
      verifyBookingId: bookingId,
      verifiedRoute: verifiedRoute ?? Routes.success,
      notPaidMessage: tr.tr('psNotPaidBooking'),
    );

/// „Platba se ověřuje" pro doplatek úpravy / výměny motorky.
PaymentOutcome pendingEditOutcome(
  AppTranslations tr, {
  required String bookingId,
  double? expectedTotal,
  bool intentOnly = false,
  required PaymentOutcome verified,
}) =>
    PaymentOutcome(
      kind: PaymentOutcomeKind.pending,
      title: tr.tr('psPendingTitle'),
      subtitle: tr.tr('psPendingSub'),
      nextStepNote: tr.tr('psPendingBodyEdit'),
      ctaLabel: tr.tr('psMyReservations'),
      ctaRoute: Routes.reservations,
      verifyBookingId: bookingId,
      verifyExpectedTotal: expectedTotal,
      verifyIntentOnly: intentOnly,
      verifiedOutcome: verified,
      notPaidMessage: tr.tr('psNotPaidEdit'),
    );

/// „Platba se ověřuje" pro objednávku z e-shopu.
PaymentOutcome pendingOrderOutcome(
  AppTranslations tr, {
  required String orderId,
  required PaymentOutcome verified,
}) =>
    PaymentOutcome(
      kind: PaymentOutcomeKind.pending,
      title: tr.tr('psPendingTitle'),
      subtitle: tr.tr('psPendingSub'),
      nextStepNote: tr.tr('psPendingBodyShop'),
      ctaLabel: tr.tr('psBackToShop'),
      ctaRoute: Routes.shop,
      verifyOrderId: orderId,
      verifiedOutcome: verified,
      notPaidMessage: tr.tr('psNotPaidShop'),
    );
