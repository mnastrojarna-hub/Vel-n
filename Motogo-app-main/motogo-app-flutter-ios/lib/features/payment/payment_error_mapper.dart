import 'dart:io' show Platform;

import 'package:flutter_stripe/flutter_stripe.dart';

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

  const PaymentErrorInfo({
    required this.title,
    required this.message,
    this.retryable = true,
    this.userCancelled = false,
  });
}

/// Mapuje technické platební chyby (Stripe decline kódy, error kódy z edge funkce,
/// Google Pay chyby) na srozumitelné hlášky s konkrétní příčinou a nápravou.
///
/// Pokrývá tři vstupy:
///  - [stripeException]  — z nativního Payment Sheetu (`StripeException`)
///  - [edgeErrorCode] / [declineCode] — z odpovědi edge fn `process-payment`
///    (off-session charge: `error_code` = Stripe error code, `decline_code` = bankovní důvod)
///  - [rawMessage]       — fallback text serveru/Stripe, když kód neznáme
class PaymentErrorMapper {
  PaymentErrorMapper._();

  static PaymentErrorInfo fromStripeException(StripeException e, String lang) {
    final code = e.error.code;
    if (code == FailureCode.Canceled) {
      return _cancelled(lang);
    }
    // `stripeErrorCode` nese technické kódy karty (expired_card, incorrect_cvc,
    // card_declined, authentication_required, processing_error…). Bankovní
    // decline_code Stripe SDK na klientu spolehlivě neplní (chodí ze serveru
    // přes off-session větev — viz `fromEdge`), proto zde mapujeme jen errorCode.
    final stripeCode = e.error.stripeErrorCode;
    final mapped = _fromCodes(
      declineCode: null,
      errorCode: stripeCode,
      lang: lang,
    );
    if (mapped != null) return mapped;
    // Neznámý kód — použij lokalizovaný text od Stripe, jinak generický.
    final loc = e.error.localizedMessage;
    if (loc != null && loc.trim().isNotEmpty) {
      return PaymentErrorInfo(
        title: _t(lang, 'cardDeclinedTitle'),
        message: '$loc\n\n${_t(lang, 'genericFix')}',
      );
    }
    return _generic(lang);
  }

  /// Z odpovědi edge fn (off-session charge selhal).
  static PaymentErrorInfo fromEdge({
    String? errorCode,
    String? declineCode,
    String? rawMessage,
    required String lang,
  }) {
    final mapped = _fromCodes(
      declineCode: declineCode,
      errorCode: errorCode,
      lang: lang,
    );
    if (mapped != null) return mapped;
    if (rawMessage != null && rawMessage.trim().isNotEmpty) {
      return PaymentErrorInfo(
        title: _t(lang, 'cardDeclinedTitle'),
        message: '$rawMessage\n\n${_t(lang, 'genericFix')}',
      );
    }
    return _generic(lang);
  }

  /// Google Pay / Apple Pay selhání (např. OR_BIBED_11) — typicky nedostupná
  /// peněženka na zařízení/účtu. Navádíme na zaplacení kartou.
  static PaymentErrorInfo wallet(String lang, {String? rawCode}) {
    final extra = (rawCode != null && rawCode.trim().isNotEmpty)
        ? '\n\n(${rawCode.trim()})'
        : '';
    return PaymentErrorInfo(
      title: _t(lang, 'walletTitle'),
      message: _t(lang, 'walletBody') + extra,
    );
  }

  static PaymentErrorInfo network(String lang) => PaymentErrorInfo(
        title: _t(lang, 'networkTitle'),
        message: _t(lang, 'networkBody'),
      );

  static PaymentErrorInfo authExpired(String lang) => PaymentErrorInfo(
        title: _t(lang, 'authExpiredTitle'),
        message: _t(lang, 'authExpiredBody'),
        retryable: false,
      );

  static PaymentErrorInfo generic(String lang) => _generic(lang);

  // ── interní ──────────────────────────────────────────────────────────────

  static PaymentErrorInfo? _fromCodes({
    String? declineCode,
    String? errorCode,
    required String lang,
  }) {
    final d = (declineCode ?? '').toLowerCase();
    final c = (errorCode ?? '').toLowerCase();

    // Nejdřív konkrétní bankovní decline kódy (nejpřesnější příčina).
    switch (d) {
      case 'insufficient_funds':
        return PaymentErrorInfo(
            title: _t(lang, 'fundsTitle'), message: _t(lang, 'fundsBody'));
      case 'lost_card':
      case 'stolen_card':
      case 'pickup_card':
        return PaymentErrorInfo(
            title: _t(lang, 'blockedTitle'), message: _t(lang, 'blockedBody'));
      case 'card_velocity_exceeded':
      case 'withdrawal_count_limit_exceeded':
        return PaymentErrorInfo(
            title: _t(lang, 'limitTitle'), message: _t(lang, 'limitBody'));
      case 'expired_card':
        return PaymentErrorInfo(
            title: _t(lang, 'expiredTitle'), message: _t(lang, 'expiredBody'));
      case 'incorrect_cvc':
      case 'invalid_cvc':
        return PaymentErrorInfo(
            title: _t(lang, 'cvcTitle'), message: _t(lang, 'cvcBody'));
      case 'incorrect_number':
      case 'invalid_number':
        return PaymentErrorInfo(
            title: _t(lang, 'numberTitle'), message: _t(lang, 'numberBody'));
      case 'do_not_honor':
      case 'transaction_not_allowed':
      case 'service_not_allowed':
      case 'currency_not_supported':
        return PaymentErrorInfo(
            title: _t(lang, 'bankBlockTitle'),
            message: _t(lang, 'bankBlockBody'));
      case 'generic_decline':
      case 'do_not_try_again':
        return PaymentErrorInfo(
            title: _t(lang, 'cardDeclinedTitle'),
            message: _t(lang, 'bankBlockBody'));
    }

    // Pak Stripe error kódy.
    switch (c) {
      case 'expired_card':
        return PaymentErrorInfo(
            title: _t(lang, 'expiredTitle'), message: _t(lang, 'expiredBody'));
      case 'incorrect_cvc':
      case 'invalid_cvc':
        return PaymentErrorInfo(
            title: _t(lang, 'cvcTitle'), message: _t(lang, 'cvcBody'));
      case 'incorrect_number':
      case 'invalid_number':
        return PaymentErrorInfo(
            title: _t(lang, 'numberTitle'), message: _t(lang, 'numberBody'));
      case 'card_declined':
        return PaymentErrorInfo(
            title: _t(lang, 'cardDeclinedTitle'),
            message: _t(lang, 'bankBlockBody'));
      case 'authentication_required':
        return PaymentErrorInfo(
            title: _t(lang, 'authTitle'), message: _t(lang, 'authBody'));
      case 'processing_error':
        return PaymentErrorInfo(
            title: _t(lang, 'processingTitle'),
            message: _t(lang, 'processingBody'));
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

  // Vlastní lokalizace (cs/en/de + fallback na cs). Záměrně self-contained,
  // ať mapper nezávisí na velkých i18n souborech a chyby jsou vždy přeložené.
  // Texty jsou psané pro Google Pay (Android master); na iOS se peněženka
  // jmenuje Apple Pay — substituce drží všechny jazyky konzistentní bez
  // duplikace celé tabulky.
  static String _t(String lang, String key) {
    final l = (lang.isEmpty ? 'cs' : lang.substring(0, lang.length.clamp(0, 2)));
    final m = _strings[l] ?? _strings['cs']!;
    final s = m[key] ?? _strings['cs']![key] ?? key;
    if (Platform.isIOS) {
      return s
          .replaceAll('Google Pay', 'Apple Pay')
          .replaceAll('Google-Pay', 'Apple-Pay');
    }
    return s;
  }

  static const Map<String, Map<String, String>> _strings = {
    'cs': {
      'cardDeclinedTitle': 'Platba kartou zamítnuta',
      'fundsTitle': 'Nedostatek prostředků',
      'fundsBody':
          'Na kartě není dostatek peněz pro tuto platbu. Dobijte prosím účet, zvolte jinou kartu, nebo zaplaťte přes Google Pay.',
      'blockedTitle': 'Karta je zablokovaná',
      'blockedBody':
          'Vaše banka tuto kartu zablokovala (nahlášena jako ztracená/odcizená). Použijte prosím jinou kartu nebo kontaktujte svou banku.',
      'limitTitle': 'Překročen limit karty',
      'limitBody':
          'Byl překročen denní limit nebo počet plateb. Zvyšte limit v aplikaci své banky, zkuste to později, nebo použijte jinou kartu.',
      'expiredTitle': 'Platnost karty vypršela',
      'expiredBody':
          'Karta už není platná. Použijte prosím jinou, platnou kartu.',
      'cvcTitle': 'Chybný bezpečnostní kód (CVC)',
      'cvcBody':
          'Zadaný kód CVC (3 čísla na zadní straně karty) je nesprávný. Zkuste platbu znovu a zadejte ho pečlivě.',
      'numberTitle': 'Chybné číslo karty',
      'numberBody':
          'Zadané číslo karty není správné. Zkontrolujte ho a zkuste platbu znovu.',
      'bankBlockTitle': 'Platbu zamítla banka',
      'bankBlockBody':
          'Vaše banka tuto platbu neschválila. Kartu obvykle odblokujete přímo v aplikaci své banky (často kvůli ochraně proti podvodu). Pak zkuste platbu znovu, nebo použijte jinou kartu.',
      'authTitle': 'Potvrzení u banky se nezdařilo',
      'authBody':
          'Banka vyžadovala potvrzení platby (3D Secure), které se nepodařilo dokončit. Zkuste platbu znovu a potvrďte ji v aplikaci své banky.',
      'processingTitle': 'Dočasná chyba při zpracování',
      'processingBody':
          'Platbu se teď nepodařilo zpracovat. Chvíli počkejte a zkuste to prosím znovu.',
      'walletTitle': 'Google Pay teď nelze použít',
      'walletBody':
          'Platbu přes Google Pay se nepodařilo dokončit. Zkontrolujte, že máte v Google Pay přidanou platnou kartu, nebo zaplaťte přímo kartou — funguje vždy.',
      'networkTitle': 'Bez připojení k internetu',
      'networkBody':
          'Nepodařilo se spojit s platebním serverem. Zkontrolujte připojení k internetu a zkuste platbu znovu — žádné peníze zatím nebyly strženy.',
      'authExpiredTitle': 'Přihlášení vypršelo',
      'authExpiredBody':
          'Pro dokončení platby se prosím znovu přihlaste. Vaše rezervace zůstává uložená.',
      'cancelledTitle': 'Platba zrušena',
      'cancelledBody':
          'Platbu jste zrušili — nic nebylo strženo. Až budete chtít, můžete ji kdykoli dokončit.',
      'genericTitle': 'Platba se nezdařila',
      'genericBody':
          'Platbu se nepodařilo dokončit a žádné peníze nebyly strženy. Zkuste to prosím znovu, nebo použijte jinou platební metodu.',
      'genericFix':
          'Zkuste platbu znovu, použijte jinou kartu, nebo zaplaťte přes Google Pay.',
    },
    'en': {
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
          'Your bank required confirmation (3D Secure) that could not be completed. Try again and confirm it in your bank app.',
      'processingTitle': 'Temporary processing error',
      'processingBody':
          'The payment could not be processed right now. Please wait a moment and try again.',
      'walletTitle': 'Google Pay unavailable',
      'walletBody':
          'The Google Pay payment could not be completed. Make sure you have a valid card in Google Pay, or pay by card directly — that always works.',
      'networkTitle': 'No internet connection',
      'networkBody':
          'Could not reach the payment server. Check your connection and try again — no money has been charged yet.',
      'authExpiredTitle': 'Session expired',
      'authExpiredBody':
          'Please sign in again to finish the payment. Your reservation is saved.',
      'cancelledTitle': 'Payment cancelled',
      'cancelledBody':
          'You cancelled the payment — nothing was charged. You can finish it anytime.',
      'genericTitle': 'Payment failed',
      'genericBody':
          'The payment could not be completed and no money was charged. Please try again or use another payment method.',
      'genericFix':
          'Try again, use another card, or pay with Google Pay.',
    },
    'de': {
      'cardDeclinedTitle': 'Kartenzahlung abgelehnt',
      'fundsTitle': 'Nicht genügend Guthaben',
      'fundsBody':
          'Auf der Karte ist nicht genug Guthaben für diese Zahlung. Laden Sie Ihr Konto auf, wählen Sie eine andere Karte oder zahlen Sie mit Google Pay.',
      'blockedTitle': 'Karte ist gesperrt',
      'blockedBody':
          'Ihre Bank hat diese Karte gesperrt (als verloren/gestohlen gemeldet). Bitte verwenden Sie eine andere Karte oder kontaktieren Sie Ihre Bank.',
      'limitTitle': 'Kartenlimit überschritten',
      'limitBody':
          'Das Tageslimit oder die Anzahl der Zahlungen wurde überschritten. Erhöhen Sie das Limit in Ihrer Bank-App, versuchen Sie es später oder nutzen Sie eine andere Karte.',
      'expiredTitle': 'Karte abgelaufen',
      'expiredBody':
          'Die Karte ist nicht mehr gültig. Bitte verwenden Sie eine gültige Karte.',
      'cvcTitle': 'Falscher Sicherheitscode (CVC)',
      'cvcBody':
          'Der CVC-Code (3 Ziffern auf der Kartenrückseite) ist falsch. Versuchen Sie es erneut und geben Sie ihn sorgfältig ein.',
      'numberTitle': 'Falsche Kartennummer',
      'numberBody':
          'Die Kartennummer ist falsch. Bitte überprüfen Sie sie und versuchen Sie es erneut.',
      'bankBlockTitle': 'Zahlung von Bank abgelehnt',
      'bankBlockBody':
          'Ihre Bank hat diese Zahlung nicht genehmigt. Sie können die Karte meist in Ihrer Bank-App entsperren (oft Betrugsschutz) und es dann erneut versuchen oder eine andere Karte nutzen.',
      'authTitle': 'Bankbestätigung fehlgeschlagen',
      'authBody':
          'Ihre Bank verlangte eine Bestätigung (3D Secure), die nicht abgeschlossen wurde. Versuchen Sie es erneut und bestätigen Sie in Ihrer Bank-App.',
      'processingTitle': 'Vorübergehender Verarbeitungsfehler',
      'processingBody':
          'Die Zahlung konnte gerade nicht verarbeitet werden. Bitte warten Sie kurz und versuchen Sie es erneut.',
      'walletTitle': 'Google Pay nicht verfügbar',
      'walletBody':
          'Die Google-Pay-Zahlung konnte nicht abgeschlossen werden. Stellen Sie sicher, dass Sie eine gültige Karte in Google Pay haben, oder zahlen Sie direkt mit Karte — das funktioniert immer.',
      'networkTitle': 'Keine Internetverbindung',
      'networkBody':
          'Der Zahlungsserver war nicht erreichbar. Prüfen Sie Ihre Verbindung und versuchen Sie es erneut — es wurde noch nichts abgebucht.',
      'authExpiredTitle': 'Sitzung abgelaufen',
      'authExpiredBody':
          'Bitte melden Sie sich erneut an, um die Zahlung abzuschließen. Ihre Reservierung bleibt gespeichert.',
      'cancelledTitle': 'Zahlung abgebrochen',
      'cancelledBody':
          'Sie haben die Zahlung abgebrochen — es wurde nichts abgebucht. Sie können sie jederzeit abschließen.',
      'genericTitle': 'Zahlung fehlgeschlagen',
      'genericBody':
          'Die Zahlung konnte nicht abgeschlossen werden und es wurde nichts abgebucht. Bitte versuchen Sie es erneut oder nutzen Sie eine andere Zahlungsmethode.',
      'genericFix':
          'Versuchen Sie es erneut, nutzen Sie eine andere Karte oder zahlen Sie mit Google Pay.',
    },
  };
}
