import '../../core/payment_pending_marker.dart';
import 'stripe_service.dart';

/// Výsledek ověření platby, jejíž výsledek appka nezná.
enum VerifyState {
  /// Server platbu potvrdil (DB).
  paid,
  /// Prokazatelně nezaplaceno (PaymentIntent zamítnutý / nedokončený) —
  /// zákazník smí platit znovu.
  notPaid,
  /// Pořád nevíme / banka ještě zpracovává — NEnabízet další platbu.
  pending,
}

/// Ověří platbu podle DB (zdroj pravdy = webhook) a, je-li na zařízení znám
/// PaymentIntent, i podle stavu u Stripe. Každý dotaz má timeout, takže
/// ověření nikdy nevisí. [expectedTotal] = doplatek úpravy (booking je `paid`
/// už z původní platby, důkazem je nová cena). [intentOnly] = v DB není
/// spolehlivý důkaz (doplatek výměny motorky) → rozhoduje jen stav u Stripe
/// (Succeeded = zaplaceno, výměnu dopíše webhook).
Future<VerifyState> verifyPayment({
  String? bookingId,
  String? orderId,
  double? expectedTotal,
  bool intentOnly = false,
  int attempts = 1,
  Duration interval = const Duration(seconds: 2),
}) async {
  final id = orderId ?? bookingId;
  if (id == null) return VerifyState.pending;
  var paid = false;
  if (intentOnly) {
    // DB důkaz neexistuje — rozhodne stav PaymentIntentu níže.
  } else if (orderId != null) {
    paid = await StripeService.pollOrderPaymentStatus(orderId,
        maxAttempts: attempts, interval: interval);
  } else if (expectedTotal != null) {
    paid = await StripeService.pollBookingTotal(bookingId!, expectedTotal,
        maxAttempts: attempts, interval: interval);
  } else {
    paid = await StripeService.pollBookingPaymentStatus(bookingId!,
        maxAttempts: attempts, interval: interval);
  }
  if (paid) {
    await PaymentPendingMarker.clear(id);
    return VerifyState.paid;
  }
  final marker = await PaymentPendingMarker.get(id);
  // Rozhoduje JEN PaymentIntent posledního pokusu — intent z dřívějšího,
  // opuštěného pokusu (zavřený sheet) je nezaplacený, i když teď prošlo
  // stržení uložené karty → „nic nestrženo" by vedlo k druhé platbě.
  final cs = (marker?.clientSecretCurrent ?? false) ? marker!.clientSecret : null;
  if (cs != null) {
    final o = StripeService.outcomeForStatus(await StripeService.fetchIntentStatus(cs));
    if (intentOnly && o == NextActionOutcome.succeeded) {
      await PaymentPendingMarker.clear(id);
      return VerifyState.paid;
    }
    if (o == NextActionOutcome.failed || o == NextActionOutcome.notCompleted) {
      await PaymentPendingMarker.clear(id);
      return VerifyState.notPaid;
    }
  }
  return VerifyState.pending;
}
