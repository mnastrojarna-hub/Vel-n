import '../../core/currency.dart';
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
  /// Částka pod minimem karty (15 Kč) → upravit / napsat nám.
  belowMinimum,
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

class PayProblem {
  final String title;
  final String message;
  final PayAction action;
  final double? serverTotal;
  /// Nabídnout i „Napsat nám".
  final bool contact;
  /// Počítat jako neúspěšný pokus o platbu (karta/síť) — serverová odmítnutí
  /// (cena, minimum, stav) pokusy nespotřebovávají.
  final bool countsAsAttempt;

  const PayProblem(this.title, this.message, this.action,
      {this.serverTotal, this.contact = false, this.countsAsAttempt = false});
}

/// Minimální částka platby kartou v CZK (Stripe). Pod ní karta vždy selže.
const stripeMinCzk = 15;

/// Částka, kterou kartou zaplatit NEJDE (0 < amount < 15 Kč).
bool belowCardMinimum(num amount) =>
    amount.round() > 0 && amount.round() < stripeMinCzk;

/// Odmítnutí / chyby `process-payment` → srozumitelná hláška + akce podle flow.
/// Nikdy nevrací syrový text serveru (česky) ani Stripe (anglicky).
class PaymentRefusals {
  PaymentRefusals._();

  static String _t(String lang, String key) => PaymentErrorMapper.text(lang, key);

  /// Kód odmítnutí — ze `code`, jinak odvozený z textu / HTTP stavu (část
  /// odpovědí process-payment kód zatím neposílá, viz D4 v reportu).
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

  static String _belowMinText(String lang, PayFlow flow, num amount) {
    final key = switch (flow) {
      PayFlow.edit => 'psBelowMinEdit',
      PayFlow.swap => 'psBelowMinSwap',
      PayFlow.shop => 'psBelowMinShop',
      _ => 'psBelowMinBooking',
    };
    return _t(lang, key).replaceAll('{amount}', Money.czk(amount));
  }

  /// Hláška pro částku pod minimem karty (kontrola PŘED platbou).
  static PayProblem belowMinimum(String lang, PayFlow flow, num amount) =>
      PayProblem(_t(lang, 'psBelowMinTitle'), _belowMinText(lang, flow, amount),
          PayAction.belowMinimum, contact: true);

  static String _authText(String lang, PayFlow flow) => switch (flow) {
        PayFlow.edit || PayFlow.swap => _t(lang, 'psAuthEdit'),
        PayFlow.shop => _t(lang, 'psAuthShop'),
        _ => _t(lang, 'psAuthBooking'),
      };

  /// Hlavní rozhodnutí: co ukázat po neúspěšném `createPaymentIntent`.
  /// [amount] = částka, kterou appka posílala (pro hlášku o minimu).
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
        final n = PaymentErrorMapper.network(lang);
        return PayProblem(n.title, n.message, PayAction.retry,
            countsAsAttempt: true);
      case PaymentErrorCode.serverUnavailable:
        final s = PaymentErrorMapper.serverUnavailable(lang);
        return PayProblem(s.title, s.message, PayAction.retry,
            contact: true, countsAsAttempt: true);
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
          return PayProblem(title, _t(lang, 'psRefusalUnknown'), PayAction.reloadEdit,
              contact: true);
        }
        return PayProblem(title, _t(lang, flow == PayFlow.shop ? 'psOrderAlreadyPaid' : 'psAlreadyPaid'),
            PayAction.success);
      case 'payment_in_progress':
        return PayProblem(_t(lang, 'psPendingTitle'), _t(lang, 'psPendingBody'),
            PayAction.pending);
      case 'below_minimum':
        return belowMinimum(lang, flow, amount);
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
          return PayProblem(
              _t(lang, 'psPriceChangedTitle'),
              _t(lang, 'psPriceChangedBody').replaceAll('{amount}', Money.czk(total)),
              PayAction.priceChanged,
              serverTotal: total);
        }
        return PayProblem(title, _t(lang, 'psRefusalUnknown'), PayAction.retry,
            contact: true);
      case 'free_mismatch':
        if (total != null && total > 0) {
          return PayProblem(
              _t(lang, 'psFreeRemainderTitle'),
              _t(lang, 'psFreeRemainderBody').replaceAll('{amount}', Money.czk(total)),
              PayAction.priceChanged,
              serverTotal: total);
        }
        return PayProblem(_t(lang, 'psFreeRemainderTitle'),
            _t(lang, 'psFreeCheckFailedBody'), PayAction.editBooking,
            contact: true);
      case 'free_confirm_failed':
        return PayProblem(_t(lang, 'psFreeFailedTitle'),
            _t(lang, 'psFreeFailedBody'), PayAction.retry, contact: true);
      case 'delivery_fee_guard':
      case 'location_requires_route':
        return PayProblem(title, _t(lang, 'psRefDelivery'), PayAction.editAddress);
      case 'forbidden':
        return PayProblem(
            title,
            switch (flow) {
              PayFlow.shop => _t(lang, 'psRefForbiddenShop'),
              PayFlow.edit || PayFlow.swap => _t(lang, 'refForbidden'),
              _ => _t(lang, 'psRefForbiddenBooking'),
            },
            PayAction.signIn);
      case 'order_not_found':
        return PayProblem(title, _t(lang, 'psRefOrderGone'), PayAction.toCart);
      case 'wrong_status':
        if (flow == PayFlow.shop) {
          return PayProblem(title, _t(lang, 'psRefOrderGone'), PayAction.toCart);
        }
        return PayProblem(title, _t(lang, 'refWrongStatus'),
            edit ? PayAction.reloadEdit : PayAction.reservations);
      case 'booking_not_found':
        return PayProblem(title, edit ? _t(lang, 'refNotFound') : _t(lang, 'psRefBookingGone'),
            PayAction.reservations);
      case 'stale_booking':
      case 'moto_unavailable':
      case 'active_pickup_time_locked':
      case 'trailer_staffed_only':
      case 'trailer_unavailable':
        return PayProblem(title, PaymentErrorMapper.serverRefusal(lang, code)!,
            PayAction.reloadEdit);
      case 'validation_unavailable':
      case 'trailer_check_unavailable':
        return PayProblem(title, PaymentErrorMapper.serverRefusal(lang, code)!,
            PayAction.retry, contact: true);
    }
    // Neznámý kód / chyba Stripe na serveru (500) — nic se nestrhlo
    // (bez payment_method_id se jen zakládá PaymentIntent).
    return PayProblem(title, _t(lang, 'psRefusalUnknown'), PayAction.retry,
        contact: true, countsAsAttempt: true);
  }
}
