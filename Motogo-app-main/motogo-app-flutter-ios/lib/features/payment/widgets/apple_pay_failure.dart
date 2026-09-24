import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/debug_logger.dart';
import '../payment_error_mapper.dart';

/// Vyhodnocení selhání Apple Pay (iOS-only soubor, používá CardPaymentSheet).
///
/// INCIDENT 2026-09-23 („nejde platit přes Apple Pay, jinde mi jde"): dřív
/// každé selhání Apple Pay skončilo jako „Platba kartou zamítnuta … nebo
/// zaplaťte přes Apple Pay" a sheet se zavřel — i když karta byla v pořádku
/// a chyba byla na straně Stripe/Apple (např. certifikát merchant ID).
/// Navíc se do logů nic nezapsalo, takže příčina nešla dohledat.
///
/// Pozn. k certifikátu merchant ID: když CHYBÍ úplně, Apple sheet po Face ID
/// ukáže „Platba nebyla dokončena" a plugin vrátí `Canceled` (nerozeznatelné
/// od zrušení zákazníkem → appka mlčí); v logu pak jsou jen `apple_pay_error`
/// s code=Canceled bez `apple_pay_result` a ve Stripe → Logs nic. Certifikát
/// z CIZÍHO CSR/účtu naopak skončí chybou Stripe → [walletFailed].
enum ApplePayFailureAction {
  /// Banka kartu v Apple Pay zamítla → stávající konkrétní hlášky + počítadlo.
  declined,

  /// PaymentIntent je ve skutečnosti zaplacený (Succeeded / RequiresCapture).
  paid,

  /// Stav nejistý (Processing, nebo stav PI nejde ověřit — typicky výpadek
  /// sítě po Face ID) → počkat na serverové potvrzení, NIKDY netvrdit „nic
  /// nebylo strženo" a nenabízet další platbu naslepo.
  processing,

  /// Peníze neodešly → zůstat v sheetu (karta hned pod tlačítkem, stejný PI)
  /// a ukázat [ApplePayFailureOutcome.info].
  stay,
}

class ApplePayFailureOutcome {
  const ApplePayFailureOutcome(this.action, {this.info});
  final ApplePayFailureAction action;
  final PaymentErrorInfo? info;
}

/// Kódy skutečného zamítnutí karty — mají vlastní hlášky v PaymentErrorMapper.
const _cardErrorCodes = {
  'card_declined', 'expired_card', 'incorrect_cvc', 'invalid_cvc',
  'incorrect_number', 'invalid_number', 'invalid_expiry_month',
  'invalid_expiry_year', 'processing_error', 'authentication_required',
  'insufficient_funds', 'card_velocity_exceeded',
};

bool _isCardDecline(LocalizedErrorMessage err) =>
    err.type == 'card_error' ||
    (err.declineCode ?? '').isNotEmpty ||
    _cardErrorCodes.contains(err.stripeErrorCode);

/// Rozhodne, co se sheetem po selhání Apple Pay (volat jen pro ne-Canceled).
///
/// Stav PaymentIntentu má přednost před typem chyby: stripe_ios 11.5.0 vrací
/// `Unknown` i po ÚSPĚŠNÉ platbě, když selže následný retrieve
/// (ApplePayViewController.swift), a `Failed` bez Stripe kódu jak při chybě
/// PŘED odesláním, tak při výpadku sítě PO odeslání confirmu (NSURLError) —
/// „nic nebylo strženo" se proto smí říct JEN po ověření stavu PI (nebo když
/// se Apple Pay sheet prokazatelně vůbec neotevřel).
Future<ApplePayFailureOutcome> resolveApplePayFailure(
  StripeException e, {
  required String clientSecret,
  required String lang,
}) async {
  final err = e.error;
  if (_isCardDecline(err)) {
    return const ApplePayFailureOutcome(ApplePayFailureAction.declined);
  }
  // „Payment not completed" bez Stripe kódu = STPApplePayContext se vůbec
  // nevytvořil (stripe_ios 11.5.0 StripeSdk.swift:478) → Apple Pay sheet se
  // neotevřel, nic se neodeslalo; iPhone nemá použitelnou kartu.
  final notPresented = err.code == FailureCode.Failed &&
      (err.stripeErrorCode ?? '').isEmpty &&
      err.message == 'Payment not completed';
  if (notPresented) {
    // Nic se neodeslalo → ověřovat PI netřeba (jen by zdrželo zákazníka).
    return ApplePayFailureOutcome(ApplePayFailureAction.stay,
        info: PaymentErrorMapper.wallet(lang));
  }
  final sw = Stopwatch()..start();
  final (pi, attempts) = await _retrieveWithRetry(clientSecret);
  final s = pi?.status;
  AppDebugLogger.instance.payment('apple_pay_pi_check', data: {
    'piStatus': s?.name,
    'pi': paymentIntentId(clientSecret),
    'attempts': attempts,
    'ms': sw.elapsedMilliseconds,
  });
  if (s == PaymentIntentsStatus.Succeeded ||
      s == PaymentIntentsStatus.RequiresCapture) {
    return const ApplePayFailureOutcome(ApplePayFailureAction.paid);
  }
  if (s == PaymentIntentsStatus.Processing || pi == null) {
    return const ApplePayFailureOutcome(ApplePayFailureAction.processing);
  }
  // Stav ověřen jako nezaplacený: Stripe/Apple platbu nezpracoval —
  // „zkontrolujte kartu" by zákazníka jen mátlo.
  return ApplePayFailureOutcome(ApplePayFailureAction.stay,
      info: PaymentErrorMapper.walletFailed(lang, rawCode: _supportCode(err)));
}

/// Stav PI až 3× (s timeoutem — bez sítě by jeden pokus visel až 60 s).
/// Vrací (PI nebo null, počet pokusů).
Future<(PaymentIntent?, int)> _retrieveWithRetry(String clientSecret) async {
  for (var i = 0; i < 3; i++) {
    try {
      final pi = await Stripe.instance
          .retrievePaymentIntent(clientSecret)
          .timeout(const Duration(seconds: 8));
      return (pi, i + 1);
    } catch (_) {
      if (i < 2) await Future.delayed(Duration(milliseconds: 700 * (i + 1)));
    }
  }
  return (null, 3);
}

/// Krátký kód pro podporu (celý text chyby jde jen do app_debug_logs).
String _supportCode(LocalizedErrorMessage err) {
  for (final c in [err.stripeErrorCode, err.type]) {
    if (c != null && c.trim().isNotEmpty) return 'AP-${c.trim()}';
  }
  return 'AP-${err.code.name}';
}

/// Zapíše selhání peněženky do app_debug_logs (Velín) — bez toho nešlo
/// zpětně zjistit, jestli se Apple Pay sheet vůbec otevřel a proč selhal.
void logWalletError(String wallet, StripeException e,
    {bool? supported, Map<String, dynamic>? extra}) {
  final err = e.error;
  String? cut(String? s) =>
      (s == null || s.length <= 300) ? s : s.substring(0, 300);
  AppDebugLogger.instance.payment('${wallet}_error', data: {
    'code': err.code.name,
    'stripeErrorCode': err.stripeErrorCode,
    'declineCode': err.declineCode,
    'type': err.type,
    'message': cut(err.message),
    'localizedMessage': cut(err.localizedMessage),
    'supported': supported,
    ...?extra,
  });
}

/// ID PaymentIntentu z client secretu (pro spárování logu se Stripe — secret
/// samotný se nikdy neloguje).
String paymentIntentId(String clientSecret) =>
    clientSecret.split('_secret_').first;
