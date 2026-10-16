import '../../core/currency.dart';
import 'card_minimum.dart';
import 'payment_error_mapper.dart';
import 'stripe_service.dart';

/// Odkud se platí — podle toho se liší text i akce (úprava ≠ nová rezervace).
enum PayFlow { booking, resume, edit, swap, shop }

/// Co má hláška nabídnout jako hlavní krok (tlačítko vždy něco DĚLÁ).
enum PayAction {
  /// Zkusit znovu (nic nestrženo).
  retry,
  /// Už zaplaceno / platba není potřeba → dokončit jako úspěch.
  success,
  /// Server spočítal jinou cenu → nabídnout zaplacení `serverTotal`.
  priceChanged,
  /// Zbývá méně než minimum karty → „Zaplatit 15 Kč" (dorovnání, D1).
  payMin,
  /// Platba už běží → obrazovka „Platba se ověřuje" (žádná další platba).
  pending,
  /// Nevíme, jestli platba prošla → ověřit stav v DB.
  verify,
  /// Zpět na úpravu rezervace a načíst ji znovu.
  reloadEdit,
  /// Zpět na úpravu — zadat adresu znovu.
  editAddress,
  /// Zpět na rezervační formulář.
  editBooking,
  /// Zpět do košíku (objednávku odeslat znovu).
  toCart,
  /// Přihlásit se znovu.
  signIn,
  /// Otevřít Rezervace.
  reservations,
}

/// Hláška k neúspěšné platbě. D5 (2026-10-16): žádné kontakty — text vždy
/// říká, co se stalo, jestli se něco strhlo a jak to napravit.
class PayProblem {
  final String title;
  final String message;
  final PayAction action;
  /// Částka pro akci: nová cena (`priceChanged`) / serverová `due` (`payMin`).
  final double? serverTotal;
  /// Počítat jako neúspěšný pokus o platbu (karta/síť) — serverová odmítnutí
  /// (cena, minimum, stav) pokusy nespotřebovávají.
  final bool countsAsAttempt;

  const PayProblem(this.title, this.message, this.action,
      {this.serverTotal, this.countsAsAttempt = false});
}

/// Odmítnutí / chyby `process-payment` → srozumitelná hláška + akce podle flow.
/// Nikdy nevrací syrový text serveru (česky) ani Stripe (anglicky).
class PaymentRefusals {
  PaymentRefusals._();

  static String _t(String lang, String key) => PaymentErrorMapper.text(lang, key);

  /// Kód odmítnutí — ze `code`, jinak odvozený z textu / HTTP stavu (starší
  /// odpovědi process-payment kód neposílaly).
  static String? codeOf(PaymentResult r) {
    final c = r.serverCode;
    if (c != null && c.isNotEmpty) return c;
    final m = (r.errorMessage ?? '').toLowerCase();
    if (m.contains('již zaplacena') || m.contains('už zaplacená')) return 'already_paid';
    if (m.contains('amount must be at least') ||
        m.contains('amount_too_small') ||
        m.contains('minimální částka')) {
      return 'below_minimum';
    }
    if (m.contains('neodpovídá ceně rezervace') || m.contains('sleva není 100')) {
      return 'free_mismatch';
    }
    if (m.contains('potvrzení rezervace selhalo')) return 'free_confirm_failed';
    if (m.contains('missing booking_id')) return 'booking_not_found';
    return null;
  }

  /// Cena ze serveru: pole `server_total`/`expected`, jinak „(1234 Kč)" v textu.
  static double? totalOf(PaymentResult r) {
    if (r.serverTotal != null) return r.serverTotal;
    final m = RegExp(r'\((\d+(?:[.,]\d+)?) Kč\)').firstMatch(r.errorMessage ?? '');
    return m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }

  /// Zbývá méně než 15 Kč (server `below_minimum` / Stripe `amount_too_small`)
  /// → zaplatit 15 Kč, rozdíl je na dokladu jako dorovnání (D1).
  static PayProblem belowMinimum(String lang, num due) {
    final cc = cardCharge(due);
    final body = due > 0 && cc.isRound
        ? _t(lang, 'pdBelowMinBody')
            .replaceAll('{amount}', kcExact(due))
            .replaceAll('{rounding}', kcExact(cc.rounding))
        : _t(lang, 'pdBelowMinGeneric');
    return PayProblem(_t(lang, 'pdBelowMinTitle'), body, PayAction.payMin,
        serverTotal: due > 0 ? due.toDouble() : null);
  }

  static String _authText(String lang, PayFlow flow) => switch (flow) {
        PayFlow.edit || PayFlow.swap => _t(lang, 'psAuthEdit'),
        PayFlow.shop => _t(lang, 'psAuthShop'),
        _ => _t(lang, 'psAuthBooking'),
      };

  /// Chyba serveru / neznámý kód — nic se nestrhlo, zkusit znovu.
  static PayProblem _server(String lang, {bool counts = false}) => PayProblem(
      _t(lang, 'pdServerTitle'), _t(lang, 'pdUnknownBody'), PayAction.retry,
      countsAsAttempt: counts);

  /// Kódy výměny motorky (dry-run / zápis `split_booking_moto_swap`) → přesné
  /// texty (co se stalo, že se nic nestrhlo, co udělat) — sdílí je i sekce
  /// výměny v úpravě rezervace.
  static const swapCodes = <String, String>{
    'not_found': 'pdSwapNotFound',
    'not_paid': 'pdSwapNotPaid',
    'invalid_new_moto': 'pdSwapInvalidMoto',
    'swap_date_out_of_range': 'pdSwapDateRange',
    'already_split': 'pdSwapAlreadySplit',
    'license_insufficient': 'pdSwapLicense',
    'new_moto_unavailable': 'pdSwapUnavailable',
    'forbidden': 'pdSwapForbidden',
    'wrong_status': 'pdSwapWrongStatus',
  };

  /// Server vrátil jinou cenu ([total]) — s pravidlem minima karty (D1): pod
  /// 15 Kč „Zaplatit 15 Kč" s vysvětlením dorovnání, do 1 Kč „Potvrdit bez
  /// platby" (nic se nestrhne), jinak „Zaplatit {cena}".
  static PayProblem _newPrice(String lang, String title, String body, double total) {
    final cc = cardCharge(total);
    if (cc.isRound) return belowMinimum(lang, total);
    if (cc.isWaive) {
      return PayProblem(title, _t(lang, 'pdWaiveNote').replaceAll('{amount}', kcExact(total)),
          PayAction.priceChanged,
          serverTotal: total);
    }
    return PayProblem(title, _t(lang, body).replaceAll('{amount}', Money.czk(total)),
        PayAction.priceChanged,
        serverTotal: total);
  }

  /// Hlavní rozhodnutí: co ukázat po neúspěšném `createPaymentIntent`.
  /// [amount] = serverová částka k zaplacení, ze které appka vycházela.
  static PayProblem resolve(String lang, PaymentResult r, PayFlow flow,
      {required num amount}) {
    final title = _t(lang, 'psRefusalTitle');
    final edit = flow == PayFlow.edit || flow == PayFlow.swap;

    // Odpověď se ztratila po odeslání stržení uložené karty → ověřit.
    if (r.uncertain) {
      final u = PaymentErrorMapper.uncertain(lang);
      return PayProblem(u.title, u.message, PayAction.verify);
    }
    switch (r.errorCode) {
      case PaymentErrorCode.authExpired:
        return PayProblem(_t(lang, 'authExpiredTitle'), _authText(lang, flow),
            PayAction.signIn);
      case PaymentErrorCode.timeout:
      case PaymentErrorCode.networkError:
        // Bez spojení se nic neodeslalo → nejde o pokus kartou (rada „zkus
        // jinou kartu" po třetím výpadku by byla špatně).
        final n = PaymentErrorMapper.network(lang);
        return PayProblem(n.title, n.message, PayAction.retry);
      case PaymentErrorCode.serverUnavailable:
        final s = PaymentErrorMapper.serverUnavailable(lang);
        return PayProblem(s.title, s.message, PayAction.retry);
      default:
        break;
    }

    final code = codeOf(r);
    final total = totalOf(r);
    switch (code) {
      case 'already_paid':
      case 'no_payment_needed':
        // U doplatku úpravy „zaplaceno" znamená původní platbu, ne doplatek →
        // nikdy nedokončovat úpravu jako zaplacenou.
        if (edit) {
          return PayProblem(_t(lang, 'pdChangeNaTitle'), _t(lang, 'pdChangeNaBody'),
              PayAction.reloadEdit);
        }
        return PayProblem(title, _t(lang, flow == PayFlow.shop ? 'psOrderAlreadyPaid' : 'psAlreadyPaid'),
            PayAction.success);
      case 'payment_in_progress':
        // Doplatek PŘEDCHOZÍ úpravy se ještě zpracovává / zapisuje — tahle
        // nová úprava se nezaplatila (nečekat na ni, zkusit ji za chvíli).
        if (edit && r.previousChange) {
          return PayProblem(_t(lang, 'pdPrevChangeTitle'), _t(lang, 'pdPrevChangeBody'),
              PayAction.reloadEdit);
        }
        return PayProblem(
            _t(lang, 'psPendingTitle'),
            _t(lang, edit ? 'psPendingBodyEdit' : flow == PayFlow.shop ? 'psPendingBodyShop' : 'psPendingBody'),
            PayAction.pending);
      case 'duplicate_request':
        final u = PaymentErrorMapper.uncertain(lang);
        return PayProblem(u.title, u.message, PayAction.verify);
      case 'below_minimum':
        return belowMinimum(lang, r.serverDue ?? amount);
      case 'rounding_unavailable':
        return PayProblem(_t(lang, 'pdRoundUnavTitle'), _t(lang, 'pdRoundUnavBody'),
            PayAction.retry);
      case 'booking_cancelled':
        return PayProblem(_t(lang, 'pdCancelledTitle'), _t(lang, 'pdCancelledBody'),
            PayAction.reservations);
      case 'voucher_unavailable':
        return PayProblem(
            _t(lang, 'pdVoucherTitle'),
            _t(lang, 'pdVoucherBody').replaceAll('{code}', r.detail ?? ''),
            flow == PayFlow.booking ? PayAction.editBooking : PayAction.reservations);
      case 'auth_required':
        return PayProblem(_t(lang, 'authExpiredTitle'), _authText(lang, flow),
            PayAction.signIn);
      case 'amount_mismatch':
        if (flow == PayFlow.shop) {
          return PayProblem(
              _t(lang, 'psPriceChangedTitle'),
              _t(lang, 'psShopPriceChangedBody')
                  .replaceAll('{amount}', Money.czk(total ?? 0)),
              PayAction.toCart);
        }
        if (edit) {
          return PayProblem(
              _t(lang, 'psPriceChangedTitle'),
              total != null
                  ? _t(lang, 'psEditPriceChangedBody').replaceAll('{amount}', Money.czk(total))
                  : _t(lang, 'refAmountMismatch'),
              PayAction.reloadEdit);
        }
        if (total != null && total > 0) {
          return _newPrice(lang, _t(lang, 'psPriceChangedTitle'), 'psPriceChangedBody', total);
        }
        return _server(lang);
      case 'free_mismatch':
        if (total != null && total > 0) {
          return _newPrice(lang, _t(lang, 'psFreeRemainderTitle'), 'psFreeRemainderBody', total);
        }
        return PayProblem(_t(lang, 'psFreeRemainderTitle'),
            _t(lang, 'pdFreeCheckFailedBody'), PayAction.editBooking);
      case 'free_confirm_failed':
        return PayProblem(_t(lang, 'psFreeFailedTitle'),
            _t(lang, 'psFreeFailedBody'), PayAction.retry);
      case 'change_too_large':
        return PayProblem(_t(lang, 'pdTooLargeTitle'), _t(lang, 'pdTooLargeBody'),
            PayAction.reloadEdit);
      case 'change_not_applicable':
        return PayProblem(_t(lang, 'pdChangeNaTitle'), _t(lang, 'pdChangeNaBody'),
            PayAction.reloadEdit);
      case 'stripe_unavailable':
        return PayProblem(_t(lang, 'pdGatewayTitle'), _t(lang, 'pdGatewayBody'),
            PayAction.retry);
      case 'delivery_fee_guard':
      case 'location_requires_route':
        return PayProblem(title, _t(lang, 'psRefDelivery'), PayAction.editAddress);
      case 'forbidden':
        return PayProblem(
            title,
            switch (flow) {
              PayFlow.shop => _t(lang, 'psRefForbiddenShop'),
              PayFlow.swap => _t(lang, 'pdSwapForbidden'),
              PayFlow.edit => _t(lang, 'refForbidden'),
              _ => _t(lang, 'psRefForbiddenBooking'),
            },
            PayAction.signIn);
      case 'order_not_found':
        return PayProblem(title, _t(lang, 'psRefOrderGone'), PayAction.toCart);
      case 'wrong_status':
        if (flow == PayFlow.shop) {
          return PayProblem(title, _t(lang, 'psRefOrderGone'), PayAction.toCart);
        }
        return PayProblem(title, _t(lang, flow == PayFlow.swap ? 'pdSwapWrongStatus' : 'refWrongStatus'),
            edit ? PayAction.reloadEdit : PayAction.reservations);
      case 'booking_not_found':
        return PayProblem(title, edit ? _t(lang, 'refNotFound') : _t(lang, 'psRefBookingGone'),
            PayAction.reservations);
      case 'stale_booking':
        // Rezervaci změnila PŘEDCHOZÍ zaplacená úprava zákazníka (právě se
        // dopsala) — ne „jiné zařízení nebo web".
        if (r.previousChange) {
          return PayProblem(title, _t(lang, 'pdPrevAppliedBody'), PayAction.reloadEdit);
        }
        return PayProblem(title, PaymentErrorMapper.serverRefusal(lang, code)!,
            PayAction.reloadEdit);
      case 'moto_unavailable':
      case 'active_pickup_time_locked':
      case 'trailer_staffed_only':
      case 'trailer_unavailable':
        return PayProblem(title, PaymentErrorMapper.serverRefusal(lang, code)!,
            PayAction.reloadEdit);
      case 'validation_unavailable':
      case 'trailer_check_unavailable':
        if (!edit) {
          // Platba rezervace / SOS: server ji teď nedokázal ověřit (ne „změna").
          final s = PaymentErrorMapper.serverUnavailable(lang);
          return PayProblem(s.title, s.message, PayAction.retry);
        }
        return PayProblem(title, PaymentErrorMapper.serverRefusal(lang, code)!,
            PayAction.retry);
      case 'server_error':
      case 'invalid_type':
      case 'missing_booking_id':
      case 'missing_order_id':
      case 'invalid_amount':
        return _server(lang);
    }
    final swapKey = swapCodes[code];
    if (swapKey != null) return PayProblem(title, _t(lang, swapKey), PayAction.reloadEdit);
    // Neznámý kód / chyba bez kódu (starší server) — nic se nestrhlo (bez
    // payment_method_id se jen zakládá PaymentIntent). Chyba serveru (5xx)
    // není neúspěšný pokus kartou.
    final status = r.httpStatus;
    return _server(lang, counts: status == null || status < 500);
  }
}
