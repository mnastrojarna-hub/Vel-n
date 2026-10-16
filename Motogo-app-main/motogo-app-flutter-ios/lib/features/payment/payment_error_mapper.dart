import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../core/i18n/translations.dart';
import 'payment_error_strings_a.dart';
import 'payment_error_strings_b.dart';
import 'payment_error_strings_c.dart';
import 'stripe_service.dart' show PaymentErrorCode;

/// Strukturovaný výsledek mapování platební chyby.
/// Zákazník nikdy nesmí zůstat v nejistotě — pro každý známý problém vrací
/// konkrétní titulek, vysvětlení příčiny a návod, jak ho napravit.
class PaymentErrorInfo {
  final String title;
  final String message;
  /// true = má smysl zkusit znovu / jinou kartu (declined, funds, network…).
  /// false = terminální (zrušeno uživatelem) — neukazujeme „zkusit znovu" jako chybu.
  final bool retryable;
  /// true = uživatel jen zrušil platbu (Payment Sheet zavřel) → není to chyba.
  final bool userCancelled;
  /// true = z chyby nejde poznat, jestli platba prošla (výpadek spojení po
  /// odeslání, `payment_intent_unexpected_state`) → volající MUSÍ ověřit stav
  /// platby a nesmí tvrdit „nic nebylo strženo".
  final bool needsVerification;
  /// Normalizovaná příčina pro volbu akce (`card_gone`, `amount_too_small`…).
  final String? cause;

  const PaymentErrorInfo({
    required this.title,
    required this.message,
    this.retryable = true,
    this.userCancelled = false,
    this.needsVerification = false,
    this.cause,
  });
}

/// Mapuje technické platební chyby (Stripe decline kódy, error kódy z edge funkce,
/// Google Pay chyby) na srozumitelné hlášky s konkrétní příčinou a nápravou.
///
/// Syrový text Stripe/serveru se zákazníkovi NIKDY neukazuje (byl anglicky
/// nebo v jazyce telefonu, ne appky) — neznámé zamítnutí karty dostane
/// obecnou hlášku banky, neznámá ne-karetní chyba se ověřuje (needsVerification).
class PaymentErrorMapper {
  PaymentErrorMapper._();

  /// [wallet] = platilo se přes Google Pay / Apple Pay → rada nesmí znovu
  /// posílat do peněženky (smyčka), ale ke kartě.
  static PaymentErrorInfo fromStripeException(StripeException e, String lang,
      {bool wallet = false}) {
    final err = e.error;
    if (err.code == FailureCode.Canceled) {
      return _cancelled(lang);
    }
    final mapped = _fromCodes(
      declineCode: err.declineCode,
      errorCode: err.stripeErrorCode,
      lang: lang,
      wallet: wallet,
    );
    if (mapped != null) return mapped;
    if (err.type == 'card_error' || (err.declineCode ?? '').isNotEmpty ||
        (err.stripeErrorCode ?? '').isNotEmpty) {
      // Skutečné zamítnutí s kódem, který neznáme → obecná hláška banky.
      return PaymentErrorInfo(
          title: _t(lang, 'cardDeclinedTitle'),
          message: _t(lang, 'bankBlockBody'),
          cause: 'card_declined');
    }
    // Bez kódu karty (výpadek sítě po odeslání, chyba pluginu) — nevíme.
    return uncertain(lang);
  }

  /// Z odpovědi edge fn (stržení uložené karty selhalo). [rawMessage] se
  /// zákazníkovi neukazuje (anglický text Stripe) — zůstal kvůli kompatibilitě.
  /// [intentStatus] = stav PaymentIntentu, pokud ho server zná.
  ///
  /// Bez kódu Stripe A bez stavu, který stržení vylučuje: process-payment
  /// vrací `off_session_charge_failed` bez kódu i při výpadku spojení se
  /// Stripe / chybě API — požadavek mohl kartu strhnout → [uncertain]
  /// (ověřit), nikdy „nic jsme nestrhli" (+ „Zkusit znovu" = dvojí platba).
  static PaymentErrorInfo fromEdge({
    String? errorCode,
    String? declineCode,
    String? rawMessage,
    String? intentStatus,
    required String lang,
  }) {
    final mapped = _fromCodes(
      declineCode: declineCode,
      errorCode: errorCode,
      lang: lang,
    );
    if (mapped != null) return mapped;
    if ((errorCode ?? '').isNotEmpty || (declineCode ?? '').isNotEmpty) {
      return PaymentErrorInfo(
          title: _t(lang, 'cardDeclinedTitle'),
          message: _t(lang, 'bankBlockBody'),
          cause: 'card_declined');
    }
    // Jen stav PI, ve kterém peníze prokazatelně neodešly, smí říct
    // „nic jsme nestrhli".
    if (intentStatus == 'requires_payment_method' || intentStatus == 'canceled') {
      return _generic(lang);
    }
    return uncertain(lang);
  }

  /// Google Pay / Apple Pay selhání (např. OR_BIBED_11) — typicky nedostupná
  /// peněženka na zařízení/účtu. Navádíme na zaplacení kartou.
  static PaymentErrorInfo wallet(String lang, {String? rawCode}) {
    // Technický kód peněženky jen do logu — zákazníkovi nic neříká (D5).
    if (rawCode != null && rawCode.trim().isNotEmpty) debugPrint('[Pay] wallet: $rawCode');
    return PaymentErrorInfo(
      title: _t(lang, 'walletTitle'),
      message: _t(lang, 'walletBody'),
    );
  }

  /// Peněženka se otevřela, ale platbu nezpracoval Stripe/Apple (např.
  /// certifikát merchant ID z cizího CSR/účtu) — peníze neodešly (ověřeno
  /// stavem PaymentIntentu v apple_pay_failure.dart; neověřitelný stav tuto
  /// hlášku NIKDY nedostane). Na rozdíl od [wallet] zákazníka neposílá
  /// kontrolovat kartu v peněžence (ta je v pořádku), ale rovnou ke kartě.
  static PaymentErrorInfo walletFailed(String lang, {String? rawCode}) {
    if (rawCode != null && rawCode.trim().isNotEmpty) debugPrint('[Pay] wallet failed: $rawCode');
    return PaymentErrorInfo(
      title: _t(lang, 'walletFailedTitle'),
      message: _t(lang, 'walletFailedBody'),
    );
  }

  /// Bez spojení se serverem, platba se NEodeslala → „nic nestrženo" platí.
  static PaymentErrorInfo network(String lang) => PaymentErrorInfo(
        title: _t(lang, 'networkTitle'),
        message: _t(lang, 'networkBody'),
      );

  /// Spojení se přerušilo PO odeslání platby — nevíme, jestli prošla.
  static PaymentErrorInfo uncertain(String lang) => PaymentErrorInfo(
        title: _t(lang, 'psUncertainTitle'),
        message: _t(lang, 'psUncertainBody'),
        needsVerification: true,
      );

  static PaymentErrorInfo serverUnavailable(String lang) => PaymentErrorInfo(
        title: _t(lang, 'psServerDownTitle'),
        message: _t(lang, 'psServerDownBody'),
      );

  static PaymentErrorInfo authExpired(String lang) => PaymentErrorInfo(
        title: _t(lang, 'authExpiredTitle'),
        message: _t(lang, 'authExpiredBody'),
        retryable: false,
      );

  static PaymentErrorInfo generic(String lang) => _generic(lang);

  /// Chyba vrácená [StripeService] (kód, ne text — text služby je jen
  /// technický log a zákazníkovi se neukazuje): přihlášení vypršelo /
  /// síť nebo timeout / server neodpovídá / ostatní.
  static PaymentErrorInfo serviceError(String lang, PaymentErrorCode? code) =>
      switch (code) {
        PaymentErrorCode.authExpired => authExpired(lang),
        PaymentErrorCode.timeout || PaymentErrorCode.networkError => network(lang),
        PaymentErrorCode.serverUnavailable => serverUnavailable(lang),
        _ => _generic(lang),
      };

  /// Odmítnutí doplatkové změny serverem PŘED platbou (process-payment 409/403,
  /// pole `code`). Vrací přeloženou hlášku, pro neznámý kód null.
  /// Kódy: viz `dryMsgs` v process-payment/index.ts.
  static String? serverRefusal(String lang, String? code) {
    const keys = <String, String>{
      'trailer_staffed_only': 'refTrailerStaffedOnly',
      'trailer_unavailable': 'refTrailerOccupied',
      'trailer_check_unavailable': 'refCheckUnavailable',
      'validation_unavailable': 'refValidationUnavailable',
      'booking_not_found': 'refNotFound',
      'forbidden': 'refForbidden',
      'stale_booking': 'refStale',
      'amount_mismatch': 'refAmountMismatch',
      'moto_unavailable': 'refMotoUnavailable',
      'wrong_status': 'refWrongStatus',
      'active_pickup_time_locked': 'refActivePickupTimeLocked',
      'delivery_fee_guard': 'psRefDelivery',
      'location_requires_route': 'psRefDelivery',
    };
    final k = keys[code ?? ''];
    return k == null ? null : _t(lang, k);
  }

  /// Text podle klíče v jazyce [lang] (s iOS náhradou peněženky) — pro
  /// sdílené platební hlášky mimo mapper (PaymentRefusals).
  static String text(String lang, String key) => _t(lang, key);

  // ── interní ──────────────────────────────────────────────────────────────

  static PaymentErrorInfo _info(String lang, String title, String body,
          {String? cause}) =>
      PaymentErrorInfo(
          title: _t(lang, title), message: _t(lang, body), cause: cause);

  static PaymentErrorInfo? _fromCodes({
    String? declineCode,
    String? errorCode,
    required String lang,
    bool wallet = false,
  }) {
    final d = (declineCode ?? '').toLowerCase();
    final c = (errorCode ?? '').toLowerCase();
    final funds = wallet ? 'psFundsBodyCard' : 'fundsBody';

    // Nejdřív konkrétní bankovní decline kódy (nejpřesnější příčina).
    // D5: ztracená / odcizená / zadržená karta = obecné bezpečné znění banky
    // (neprozrazovat důvod — karta může být v cizích rukou).
    switch (d) {
      case 'insufficient_funds':
        return _info(lang, 'fundsTitle', funds);
      case 'lost_card':
      case 'stolen_card':
      case 'pickup_card':
        return _info(lang, 'bankBlockTitle', 'bankBlockBody', cause: 'card_declined');
      case 'currency_not_supported':
        return _info(lang, 'pdCurrencyTitle', 'pdCurrencyBody');
      case 'duplicate_transaction':
        // Banka hlásí stejnou platbu před chvílí → ověřit, neplatit znovu.
        return uncertain(lang);
      case 'card_velocity_exceeded':
      case 'withdrawal_count_limit_exceeded':
        return _info(lang, 'limitTitle', 'limitBody');
      case 'card_decline_rate_limit_exceeded':
        return _info(lang, 'psRateLimitTitle', 'psRateLimitBody');
      case 'expired_card':
        return _info(lang, 'expiredTitle', 'expiredBody');
      case 'incorrect_cvc':
      case 'invalid_cvc':
        return _info(lang, 'cvcTitle', 'cvcBody');
      case 'incorrect_number':
      case 'invalid_number':
        return _info(lang, 'numberTitle', 'numberBody');
      case 'invalid_expiry_month':
      case 'invalid_expiry_year':
        return _info(lang, 'psExpiryTitle', 'psExpiryBody');
      case 'card_not_supported':
        return _info(lang, 'psNotSupportedTitle', 'psNotSupportedBody');
      case 'incorrect_pin':
      case 'invalid_pin':
      case 'pin_try_exceeded':
      case 'offline_pin_required':
      case 'online_or_offline_pin_required':
        return _info(lang, 'psPinTitle', 'psPinBody');
      case 'issuer_not_available':
      case 'try_again_later':
      case 'reenter_transaction':
      case 'processing_error':
        return _info(lang, 'processingTitle', 'processingBody');
      case 'authentication_required':
        return _info(lang, 'authTitle', 'authBody');
      case 'do_not_honor':
      case 'transaction_not_allowed':
      case 'service_not_allowed':
      case 'fraudulent':
      case 'restricted_card':
      case 'security_violation':
      case 'not_permitted':
      case 'call_issuer':
      case 'approve_with_id':
      case 'merchant_blacklist':
      case 'no_action_taken':
      case 'revocation_of_authorization':
      case 'revocation_of_all_authorizations':
      case 'stop_payment_order':
      case 'invalid_account':
      case 'new_account_information_available':
      case 'testmode_decline':
      case 'invalid_amount':
      case 'incorrect_zip':
        return _info(lang, 'bankBlockTitle', 'bankBlockBody');
      case 'generic_decline':
      case 'do_not_try_again':
      case 'card_declined':
        return _info(lang, 'cardDeclinedTitle', 'bankBlockBody');
    }

    // Pak Stripe error kódy.
    switch (c) {
      case 'insufficient_funds':
        return _info(lang, 'fundsTitle', funds);
      case 'expired_card':
        return _info(lang, 'expiredTitle', 'expiredBody');
      case 'incorrect_cvc':
      case 'invalid_cvc':
        return _info(lang, 'cvcTitle', 'cvcBody');
      case 'incorrect_number':
      case 'invalid_number':
        return _info(lang, 'numberTitle', 'numberBody');
      case 'invalid_expiry_month':
      case 'invalid_expiry_year':
        return _info(lang, 'psExpiryTitle', 'psExpiryBody');
      case 'card_declined':
        return _info(lang, 'cardDeclinedTitle', 'bankBlockBody');
      case 'card_decline_rate_limit_exceeded':
        return _info(lang, 'psRateLimitTitle', 'psRateLimitBody');
      case 'authentication_required':
      case 'payment_intent_authentication_failure':
      case 'setup_intent_authentication_failure':
        return _info(lang, 'authTitle', 'authBody');
      case 'processing_error':
      case 'rate_limit':
      case 'api_connection_error':
        return _info(lang, 'processingTitle', 'processingBody');
      case 'amount_too_small':
        return _info(lang, 'pdBelowMinTitle', 'pdBelowMinGeneric',
            cause: 'amount_too_small');
      case 'currency_not_supported':
        return _info(lang, 'pdCurrencyTitle', 'pdCurrencyBody');
      case 'payment_method_provider_decline':
        return _info(lang, 'pdWalletDeclinedTitle', 'pdWalletDeclinedBody');
      case 'payment_intent_payment_attempt_expired':
        return _info(lang, 'pdAttemptExpiredTitle', 'pdAttemptExpiredBody');
      case 'payment_intent_payment_attempt_failed':
      case 'amount_too_large':
        return _generic(lang);
      case 'incorrect_zip':
      case 'postal_code_invalid':
      case 'invalid_amount':
      case 'testmode_decline':
        return _info(lang, 'cardDeclinedTitle', 'bankBlockBody');
      case 'duplicate_transaction':
        return uncertain(lang);
      case 'resource_missing':
      case 'payment_method_unactivated':
      case 'payment_method_not_available':
      case 'payment_method_customer_decline':
        return _info(lang, 'psCardGoneTitle', 'psCardGoneBody',
            cause: 'card_gone');
      case 'payment_intent_unexpected_state':
        // PI je v jiném stavu (např. už zaplacený) — výsledek ověřit.
        return uncertain(lang);
    }
    return null;
  }

  static PaymentErrorInfo _cancelled(String lang) => PaymentErrorInfo(
        title: _t(lang, 'cancelledTitle'),
        message: _t(lang, 'cancelledBody'),
        retryable: false,
        userCancelled: true,
      );

  static PaymentErrorInfo _generic(String lang) => PaymentErrorInfo(
        title: _t(lang, 'genericTitle'),
        message: _t(lang, 'genericBody'),
      );

  // Vlastní lokalizace (cs/en/de zde, es/fr/nl/pl/uk v payment_error_strings_*.dart);
  // novější klíče (`ps*`) jsou ve sdílených i18n souborech (translations_ext_38_*).
  // Neznámý cizí jazyk → angličtina (ne čeština).
  static String _t(String lang, String key) {
    final l = (lang.isEmpty ? 'cs' : lang.substring(0, lang.length.clamp(0, 2)));
    final m = _strings[l] ??
        paymentErrorStringsA[l] ??
        paymentErrorStringsB[l] ??
        paymentErrorStringsC[l] ??
        _strings['en']!;
    final s = m[key] ??
        translations[l]?[key] ??
        _strings['en']![key] ??
        translations['en']?[key] ??
        key;
    // Texty jsou psané pro Google Pay (Android master); na iOS se peněženka
    // jmenuje Apple Pay — substituce drží všechny jazyky konzistentní bez
    // duplikace celé tabulky.
    if (Platform.isIOS) {
      return s
          .replaceAll('Google Pay', 'Apple Pay')
          .replaceAll('Google-Pay', 'Apple-Pay');
    }
    return s;
  }

  static const Map<String, Map<String, String>> _strings = {
    'cs': {
      // Odmítnutí doplatkové změny serverem před platbou (serverRefusal).
      'refMotoUnavailable':
          'Motorka je v novém termínu už obsazená, nebo je pobočka zavřená — doplatek jsme nestrhli. Vyber si prosím jiný termín nebo motorku.',
      'refWrongStatus':
          'Rezervaci v tomhle stavu už nejde upravit (je zrušená nebo ukončená) — doplatek jsme nestrhli.',
      'refTrailerStaffedOnly':
          'Vozík jde půjčit jen k motorce z obslužné pobočky — samoobslužná ho nevydává. Vyber si motorku z obslužné pobočky, nebo vozík z rezervace odeber. Doplatek jsme nestrhli.',
      'refTrailerOccupied':
          'Vozík je v novém termínu už obsazený jinou rezervací. Vyber si jiný termín, nebo vozík z rezervace odeber. Doplatek jsme nestrhli.',
      'refCheckUnavailable':
          'Vozík u rezervace se nepodařilo ověřit — doplatek jsme nestrhli. Zkus to prosím za chvíli znovu.',
      'refValidationUnavailable':
          'Změnu rezervace se nepodařilo ověřit — doplatek jsme nestrhli. Zkus to prosím za chvíli znovu.',
      'refNotFound':
          'Rezervaci jsme nenašli — doplatek jsme nestrhli. Načti rezervaci znovu a zkus to ještě jednou.',
      'refForbidden':
          'Tuhle rezervaci nejde upravit z tohoto účtu. Přihlas se prosím účtem, kterým jsi ji vytvořil(a).',
      'refStale':
          'Rezervace se mezitím změnila (jiné zařízení nebo web). Načti ji prosím znovu a úpravu zopakuj.',
      'refActivePickupTimeLocked':
          'Motorku už máš vyzvednutou — čas vyzvednutí už nejde změnit.',
      'refAmountMismatch':
          'Částka doplatku neodpovídá výpočtu serveru. Načti rezervaci znovu a zkus to ještě jednou.',
      'cardDeclinedTitle': 'Platba kartou zamítnuta',
      'fundsTitle': 'Nedostatek peněz na kartě',
      'fundsBody':
          'Na kartě není dost peněz na tuhle platbu. Dobij si účet, zvol jinou kartu, nebo zaplať přes Google Pay.',
      'blockedTitle': 'Karta je zablokovaná',
      'blockedBody':
          'Tvoje banka tuhle kartu zablokovala (je nahlášená jako ztracená nebo odcizená). Použij prosím jinou kartu, nebo kontaktuj svou banku.',
      'limitTitle': 'Překročený limit karty',
      'limitBody':
          'Překročil(a) jsi denní limit nebo počet plateb. Zvyš si limit v aplikaci své banky, zkus to později, nebo použij jinou kartu.',
      'expiredTitle': 'Platnost karty vypršela',
      'expiredBody':
          'Karta už není platná. Použij prosím jinou, platnou kartu.',
      'cvcTitle': 'Chybný bezpečnostní kód (CVC)',
      'cvcBody':
          'Kód CVC (3 čísla na zadní straně karty) není správný. Zkus platbu znovu a zadej ho pečlivě.',
      'numberTitle': 'Chybné číslo karty',
      'numberBody':
          'Číslo karty není správné. Zkontroluj ho a zkus platbu znovu.',
      'bankBlockTitle': 'Platbu zamítla banka',
      'bankBlockBody':
          'Tvoje banka tuhle platbu neschválila. Kartu obvykle odblokuješ přímo v aplikaci své banky (často jde o ochranu proti podvodu). Pak zkus platbu znovu, nebo použij jinou kartu.',
      'authTitle': 'Potvrzení u banky se nezdařilo',
      'authBody':
          'Banka chtěla platbu potvrdit (3D Secure), ale potvrzení se nedokončilo — nic jsme nestrhli. Zkus platbu znovu a potvrď ji v aplikaci své banky.',
      'processingTitle': 'Dočasná chyba při zpracování',
      'processingBody':
          'Banka teď platbu nezpracovala — nic jsme nestrhli. Chvíli počkej a zkus to prosím znovu.',
      'walletTitle': 'Google Pay teď nejde použít',
      'walletBody':
          'Platbu přes Google Pay se nepodařilo dokončit. Zkontroluj, že máš v Google Pay přidanou platnou kartu, nebo zaplať přímo kartou — to funguje vždy.',
      'walletFailedTitle': 'Platba přes Google Pay neprošla',
      'walletFailedBody':
          'Platbu přes Google Pay se nepodařilo zpracovat — nic jsme nestrhli. Zaplať prosím kartou tady níž, nebo to zkus později znovu.',
      'networkTitle': 'Bez připojení k internetu',
      'networkBody':
          'Nepodařilo se spojit s platebním serverem. Zkontroluj připojení k internetu a zkus platbu znovu — nic jsme zatím nestrhli.',
      'authExpiredTitle': 'Přihlášení vypršelo',
      'authExpiredBody':
          'Pro dokončení platby se prosím znovu přihlas. Nic jsme nestrhli a rezervace zůstává uložená.',
      'cancelledTitle': 'Platba zrušena',
      'cancelledBody':
          'Platbu jsi zrušil(a) — nic jsme nestrhli. Dokončit ji můžeš, kdykoli budeš chtít.',
      'genericTitle': 'Platba se nezdařila',
      'genericBody':
          'Platbu se nepodařilo dokončit a nic jsme nestrhli. Zkus to prosím znovu, nebo použij jinou kartu.',
      'genericFix':
          'Zkus platbu znovu, použij jinou kartu, nebo zaplať přes Google Pay.',
    },
    'en': {
      // Odmítnutí doplatkové změny serverem před platbou (serverRefusal).
      'refMotoUnavailable':
          'The motorcycle is already booked for the new dates, or the branch is closed — the surcharge payment was cancelled. Choose different dates or another motorcycle.',
      'refWrongStatus':
          'A booking in this state can no longer be changed (cancelled or completed) — the surcharge payment was cancelled.',
      'refTrailerStaffedOnly':
          'The trailer is only available with a motorcycle from a staffed branch — the self-service branch does not hand it out. Choose a motorcycle from a staffed branch or remove the trailer from the booking. The surcharge payment was cancelled.',
      'refTrailerOccupied':
          'The trailer is already booked by another reservation for the new dates. Choose different dates or remove the trailer from the booking. The surcharge payment was cancelled.',
      'refCheckUnavailable':
          'We could not verify the trailer on this booking — the surcharge payment was cancelled, please try again in a moment.',
      'refValidationUnavailable':
          'We could not verify the booking change — the surcharge payment was cancelled, please try again in a moment.',
      'refNotFound':
          'The booking was not found — the surcharge payment was cancelled. Reload the booking and try again.',
      'refForbidden':
          'This booking cannot be edited from this account. Please sign in with the account that created it.',
      'refStale':
          'The booking has changed in the meantime (another device or the website). Please reload it and repeat the change.',
      'refActivePickupTimeLocked':
          'The motorcycle has already been picked up — the pickup time can no longer be changed.',
      'refAmountMismatch':
          'The surcharge amount does not match the server calculation. Reload the booking and try again.',
      'cardDeclinedTitle': 'Card payment declined',
      'fundsTitle': 'Insufficient funds',
      'fundsBody':
          'There are not enough funds on the card for this payment. Top up your account, choose another card, or pay with Google Pay.',
      'blockedTitle': 'Card is blocked',
      'blockedBody':
          'Your bank has blocked this card (reported lost/stolen). Please use a different card or contact your bank.',
      'limitTitle': 'Card limit exceeded',
      'limitBody':
          'Your daily limit or number of payments was exceeded. Raise the limit in your bank app, try later, or use another card.',
      'expiredTitle': 'Card expired',
      'expiredBody': 'The card is no longer valid. Please use a valid card.',
      'cvcTitle': 'Wrong security code (CVC)',
      'cvcBody':
          'The CVC code (3 digits on the back of the card) is incorrect. Try again and enter it carefully.',
      'numberTitle': 'Wrong card number',
      'numberBody':
          'The card number is incorrect. Please check it and try again.',
      'bankBlockTitle': 'Payment declined by bank',
      'bankBlockBody':
          'Your bank did not approve this payment. You can usually unblock the card in your bank app (often anti-fraud protection), then try again or use another card.',
      'authTitle': 'Bank confirmation failed',
      'authBody':
          'Your bank asked you to confirm the payment (3D Secure), but it was not completed — nothing was charged. Try again and confirm it in your bank app.',
      'processingTitle': 'Temporary processing error',
      'processingBody':
          'The bank did not process the payment right now — nothing was charged. Please wait a moment and try again.',
      'walletTitle': 'Google Pay unavailable',
      'walletBody':
          'The Google Pay payment could not be completed. Make sure you have a valid card in Google Pay, or pay by card directly — that always works.',
      'walletFailedTitle': 'Google Pay payment failed',
      'walletFailedBody':
          'The Google Pay payment could not be processed — nothing was charged. Please pay by card below, or try again later.',
      'networkTitle': 'No internet connection',
      'networkBody':
          'Could not reach the payment server. Check your connection and try again — no money has been charged yet.',
      'authExpiredTitle': 'Session expired',
      'authExpiredBody':
          'Please sign in again to finish the payment. Nothing was charged and your reservation is saved.',
      'cancelledTitle': 'Payment cancelled',
      'cancelledBody':
          'You cancelled the payment — nothing was charged. You can finish it anytime.',
      'genericTitle': 'Payment failed',
      'genericBody':
          'The payment could not be completed and no money was charged. Please try again or use another card.',
      'genericFix':
          'Try again, use another card, or pay with Google Pay.',
    },
    'de': {
      // Odmítnutí doplatkové změny serverem před platbou (serverRefusal).
      'refMotoUnavailable':
          'Das Motorrad ist im neuen Zeitraum schon gebucht oder die Filiale ist geschlossen — die Nachzahlung wurde nicht abgebucht. Wähl bitte einen anderen Zeitraum oder ein anderes Motorrad.',
      'refWrongStatus':
          'Eine Buchung in diesem Status lässt sich nicht mehr ändern (storniert oder abgeschlossen) — die Nachzahlung wurde nicht abgebucht.',
      'refTrailerStaffedOnly':
          'Den Anhänger gibt es nur zu einem Motorrad aus einer Filiale mit Personal — die Selbstbedienungsfiliale gibt ihn nicht aus. Wähl ein Motorrad aus einer Filiale mit Personal oder entferne den Anhänger aus der Buchung. Die Nachzahlung wurde nicht abgebucht.',
      'refTrailerOccupied':
          'Der Anhänger ist im neuen Zeitraum schon durch eine andere Buchung belegt. Wähl einen anderen Zeitraum oder entferne den Anhänger aus der Buchung. Die Nachzahlung wurde nicht abgebucht.',
      'refCheckUnavailable':
          'Der Anhänger dieser Buchung konnte nicht geprüft werden — die Nachzahlung wurde nicht abgebucht. Versuch es bitte gleich noch einmal.',
      'refValidationUnavailable':
          'Die Buchungsänderung konnte nicht geprüft werden — die Nachzahlung wurde nicht abgebucht. Versuch es bitte gleich noch einmal.',
      'refNotFound':
          'Die Buchung wurde nicht gefunden — die Nachzahlung wurde nicht abgebucht. Lade die Buchung neu und versuch es noch einmal.',
      'refForbidden':
          'Diese Buchung lässt sich mit diesem Konto nicht bearbeiten. Melde dich bitte mit dem Konto an, mit dem du sie erstellt hast.',
      'refStale':
          'Die Buchung hat sich inzwischen geändert (anderes Gerät oder Website). Lade sie bitte neu und wiederhole die Änderung.',
      'refActivePickupTimeLocked':
          'Du hast das Motorrad schon abgeholt — die Abholzeit lässt sich nicht mehr ändern.',
      'refAmountMismatch':
          'Der Nachzahlungsbetrag stimmt nicht mit der Serverberechnung überein. Lade die Buchung neu und versuch es noch einmal.',
      'cardDeclinedTitle': 'Kartenzahlung abgelehnt',
      'fundsTitle': 'Nicht genug Guthaben',
      'fundsBody':
          'Auf der Karte ist nicht genug Geld für diese Zahlung. Lade dein Konto auf, wähl eine andere Karte oder zahl mit Google Pay.',
      'blockedTitle': 'Karte ist gesperrt',
      'blockedBody':
          'Deine Bank hat diese Karte gesperrt (als verloren/gestohlen gemeldet). Nimm bitte eine andere Karte oder wende dich an deine Bank.',
      'limitTitle': 'Kartenlimit überschritten',
      'limitBody':
          'Das Tageslimit oder die Anzahl der Zahlungen ist überschritten. Erhöh das Limit in deiner Banking-App, versuch es später oder nimm eine andere Karte.',
      'expiredTitle': 'Karte abgelaufen',
      'expiredBody':
          'Die Karte ist nicht mehr gültig. Nimm bitte eine gültige Karte.',
      'cvcTitle': 'Falscher Sicherheitscode (CVC)',
      'cvcBody':
          'Der CVC-Code (3 Ziffern auf der Kartenrückseite) ist falsch. Versuch es noch einmal und gib ihn sorgfältig ein.',
      'numberTitle': 'Falsche Kartennummer',
      'numberBody':
          'Die Kartennummer stimmt nicht. Prüf sie bitte und versuch es noch einmal.',
      'bankBlockTitle': 'Zahlung von der Bank abgelehnt',
      'bankBlockBody':
          'Deine Bank hat diese Zahlung nicht genehmigt. Meist kannst du die Karte direkt in deiner Banking-App freigeben (oft Betrugsschutz). Versuch es dann noch einmal oder nimm eine andere Karte.',
      'authTitle': 'Bankbestätigung fehlgeschlagen',
      'authBody':
          'Deine Bank wollte die Zahlung bestätigen lassen (3D Secure), die Bestätigung wurde aber nicht abgeschlossen — es wurde nichts abgebucht. Versuch es noch einmal und bestätige sie in deiner Banking-App.',
      'processingTitle': 'Vorübergehender Verarbeitungsfehler',
      'processingBody':
          'Die Bank hat die Zahlung gerade nicht verarbeitet — es wurde nichts abgebucht. Warte kurz und versuch es bitte noch einmal.',
      'walletTitle': 'Google Pay nicht verfügbar',
      'walletBody':
          'Die Google-Pay-Zahlung konnte nicht abgeschlossen werden. Prüf, ob du eine gültige Karte in Google Pay hast, oder zahl direkt mit Karte — das klappt immer.',
      'walletFailedTitle': 'Google-Pay-Zahlung fehlgeschlagen',
      'walletFailedBody':
          'Die Google-Pay-Zahlung konnte nicht verarbeitet werden — es wurde nichts abgebucht. Zahl bitte unten mit Karte oder versuch es später noch einmal.',
      'networkTitle': 'Keine Internetverbindung',
      'networkBody':
          'Der Zahlungsserver war nicht erreichbar. Prüf deine Verbindung und versuch es noch einmal — es wurde noch nichts abgebucht.',
      'authExpiredTitle': 'Sitzung abgelaufen',
      'authExpiredBody':
          'Melde dich bitte erneut an, um die Zahlung abzuschließen. Es wurde nichts abgebucht und deine Reservierung bleibt gespeichert.',
      'cancelledTitle': 'Zahlung abgebrochen',
      'cancelledBody':
          'Du hast die Zahlung abgebrochen — es wurde nichts abgebucht. Du kannst sie jederzeit abschließen.',
      'genericTitle': 'Zahlung fehlgeschlagen',
      'genericBody':
          'Die Zahlung konnte nicht abgeschlossen werden und es wurde nichts abgebucht. Versuch es bitte noch einmal oder nimm eine andere Karte.',
      'genericFix':
          'Versuch es noch einmal, nimm eine andere Karte oder zahl mit Google Pay.',
    },
  };
}
