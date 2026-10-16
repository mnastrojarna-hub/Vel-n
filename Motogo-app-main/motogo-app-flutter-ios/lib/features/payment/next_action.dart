import 'package:flutter_stripe/flutter_stripe.dart';

// Výsledek 3D Secure (SCA) a ověření stavu PaymentIntentu — exportuje ho
// stripe_service.dart (stávající importy `stripe_service.dart show
// NextActionOutcome` dál platí).

/// Výsledek dokončení 3DS / ověření stavu PaymentIntentu.
enum NextActionOutcome {
  /// Zaplaceno (Succeeded / RequiresCapture).
  succeeded,
  /// Banka platbu ještě zpracovává — čekat na server (webhook).
  processing,
  /// Zákazník ověření u banky nedokončil (zavřel / zrušil) — nic nestrženo.
  notCompleted,
  /// Banka ověření nebo platbu zamítla — nic nestrženo.
  failed,
  /// Stav nejde zjistit (výpadek sítě) — ověřit v DB, nikdy netvrdit „nestrženo".
  unknown,
}

/// Výsledek `StripeService.handleNextActionDetailed`: stav + výjimka Stripe
/// (kódy z `last_payment_error`), pokud ji SDK vyhodilo.
class NextActionResult {
  final NextActionOutcome outcome;
  final StripeException? error;
  const NextActionResult(this.outcome, [this.error]);

  /// Výjimka z `Stripe.instance.handleNextAction` → výsledek.
  factory NextActionResult.fromException(StripeException e) {
    if (e.error.code == FailureCode.Canceled) {
      return NextActionResult(NextActionOutcome.notCompleted, e);
    }
    // Bez Stripe kódu = typicky výpadek spojení po odeslání → stav nevíme.
    // Totéž chyba spojení / API při zjišťování stavu po ověření — nikdy
    // „nic nestrženo", ověřit.
    final code = (e.error.stripeErrorCode ?? '').toLowerCase();
    if ((e.error.declineCode ?? '').isEmpty &&
        (code.isEmpty ||
            stateUnknownCodes.contains(code) ||
            stateUnknownCodes.contains(e.error.type))) {
      return NextActionResult(NextActionOutcome.unknown, e);
    }
    return NextActionResult(NextActionOutcome.failed, e);
  }

  /// Kódy, které znamenají, že selhalo SAMO ověření 3D Secure.
  static const authCodes = {
    'authentication_required',
    'payment_intent_authentication_failure',
    'setup_intent_authentication_failure',
  };

  /// Kódy / typy chyb, po kterých stav platby neznáme (spojení, API) → ověřit.
  static const stateUnknownCodes = {
    'api_connection_error',
    'api_error',
    'rate_limit',
    'rate_limit_error',
    'lock_timeout',
  };

  /// Banka platbu zamítla z jiného důvodu než neprovedeným ověřením
  /// (nedostatek prostředků, propadlá / blokovaná karta, limit…) → výjimka
  /// pro přesnou hlášku (`PaymentErrorMapper.fromStripeException`).
  /// null = selhalo samo ověření nebo kód chybí → hláška o 3D Secure.
  StripeException? get declineError {
    final e = error;
    if (outcome != NextActionOutcome.failed || e == null) return null;
    final d = (e.error.declineCode ?? '').trim().toLowerCase();
    if (d.isNotEmpty) return authCodes.contains(d) ? null : e;
    final c = (e.error.stripeErrorCode ?? '').trim().toLowerCase();
    return c.isEmpty || authCodes.contains(c) ? null : e;
  }
}
