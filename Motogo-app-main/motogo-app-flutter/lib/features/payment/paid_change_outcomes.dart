import '../../core/i18n/i18n_provider.dart';
import '../../core/paid_change_queue.dart';
import '../../core/router.dart';
import 'card_minimum.dart';
import 'payment_provider.dart';

/// Texty a výsledkové stavy zaplacené výměny / úpravy (D6, D5 — bez kontaktů,
/// vždy co se stalo, jestli se strhly peníze a co dál).

/// Důvod trvalého selhání (kód serveru) → věta s příčinou.
String paidChangeReasonText(AppTranslations tr, String? reason) {
  final key = switch (reason) {
    'new_moto_unavailable' || 'moto_unavailable' => 'pdFailTaken',
    'wrong_status' || 'not_found' || 'not_paid' => 'pdFailStatus',
    'swap_date_out_of_range' => 'pdFailDate',
    _ => 'pdFailOther',
  };
  return tr.tr(key);
}

/// Celý text selhání: příčina + co se děje s doplatkem.
String paidChangeFailureText(AppTranslations tr,
    {String? reason, String refund = 'auto', required double amount}) {
  final money = tr
      .tr(refund == 'staff' ? 'pdRefundStaff' : 'pdRefundAuto')
      .replaceAll('{amount}', kcExact(amount));
  return '${paidChangeReasonText(tr, reason)} $money';
}

/// „Výměna se dokončuje" / „Úprava se dokončuje" — platba prošla, zápis do
/// rezervace doběhne sám (fronta + server). [verified] = výsledek po dokončení.
PaymentOutcome completingOutcome(
  AppTranslations tr, {
  required bool swap,
  required String key,
  required String bookingId,
  required double amount,
  required PaymentOutcome verified,
  bool offline = false,
}) {
  final body = tr
      .tr(swap ? 'pdSwapCompletingBody' : 'pdEditCompletingBody')
      .replaceAll('{amount}', kcExact(amount));
  return PaymentOutcome(
    kind: PaymentOutcomeKind.pending,
    title: tr.tr(swap ? 'pdSwapCompletingTitle' : 'pdEditCompletingTitle'),
    subtitle: offline ? '$body ${tr.tr('pdCompletingOffline')}' : body,
    ctaLabel: tr.tr('psMyReservations'),
    ctaRoute: Routes.reservations,
    verifyBookingId: bookingId,
    // výměna se bez fronty ověřuje jen stavem platby (a podle toho texty)
    verifyIntentOnly: swap,
    completeKey: key,
    verifiedOutcome: verified,
    notPaidMessage: tr.tr('psNotPaidEdit'),
  );
}

/// Zaplacenou změnu trvale nejde zapsat — doplatek se vrací.
PaymentOutcome changeFailedOutcome(AppTranslations tr,
        {required bool swap, required String bookingId, required PaidChangeResult r, required double charge}) =>
    PaymentOutcome(
      kind: PaymentOutcomeKind.failed,
      title: tr.tr(swap ? 'pdSwapFailedTitle' : 'pdEditFailedTitle'),
      subtitle: paidChangeFailureText(tr, reason: r.reason, refund: r.refund, amount: r.amount ?? charge),
      ctaLabel: tr.tr('psOpenReservation'),
      ctaRoute: '/reservations/$bookingId',
    );

/// Řádek s dorovnáním na výsledkové obrazovce („Zaplaceno 15 Kč (z toho
/// dorovnání 8 Kč)"), nebo null bez dorovnání.
PaymentOutcomeLine? roundingLine(AppTranslations tr, CardCharge cc) {
  if (cc.isRound) {
    return PaymentOutcomeLine(
        'ℹ️',
        tr
            .tr('pdPaidWithRounding')
            .replaceAll('{charge}', kcExact(cc.charge))
            .replaceAll('{rounding}', kcExact(cc.rounding)));
  }
  if (cc.isWaive) return PaymentOutcomeLine('ℹ️', tr.tr('pdWaivedSub'));
  return null;
}
