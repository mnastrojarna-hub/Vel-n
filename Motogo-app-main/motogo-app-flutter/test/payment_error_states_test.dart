// Chybové stavy plateb (2026-10-16): každá chyba má srozumitelný text v jazyce
// appky, akci, která něco dělá, a NIKDY netvrdí „nic nestrženo", když to nevíme.
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/features/booking/promo_reasons.dart';
import 'package:motogo_app/features/payment/payment_error_mapper.dart';
import 'package:motogo_app/features/payment/payment_refusals.dart';
import 'package:motogo_app/features/payment/stripe_service.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

StripeException _se({
  FailureCode code = FailureCode.Failed,
  String? stripeCode,
  String? decline,
  String? type,
  String? localized,
}) =>
    StripeException(
      error: LocalizedErrorMessage(
        code: code,
        stripeErrorCode: stripeCode,
        declineCode: decline,
        type: type,
        localizedMessage: localized,
        message: localized,
      ),
    );

PaymentResult _refused(String text, {String? code, double? total, int status = 409}) =>
    PaymentResult.error(text,
        code: PaymentErrorCode.serverError,
        serverCode: code,
        serverTotal: total,
        httpStatus: status);

void main() {
  group('PaymentErrorMapper', () {
    test('known declines map to specific texts in every language', () {
      for (final lang in _langs) {
        final pin = PaymentErrorMapper.fromEdge(declineCode: 'pin_try_exceeded', lang: lang);
        expect(pin.title, PaymentErrorMapper.text(lang, 'psPinTitle'));
        final ns = PaymentErrorMapper.fromEdge(declineCode: 'card_not_supported', lang: lang);
        expect(ns.message, PaymentErrorMapper.text(lang, 'psNotSupportedBody'));
        final fraud = PaymentErrorMapper.fromEdge(declineCode: 'fraudulent', lang: lang);
        expect(fraud.title, PaymentErrorMapper.text(lang, 'bankBlockTitle'));
        expect(fraud.message, isNot(contains('ps')));
      }
    });

    test('saved card gone / below minimum carry a cause for the action', () {
      final gone = PaymentErrorMapper.fromEdge(errorCode: 'resource_missing', lang: 'cs');
      expect(gone.cause, 'card_gone');
      expect(gone.message, contains('Platební metody'));
      final min = PaymentErrorMapper.fromEdge(errorCode: 'amount_too_small', lang: 'en');
      expect(min.cause, 'amount_too_small');
    });

    test('raw Stripe / server text is never shown', () {
      final info = PaymentErrorMapper.fromEdge(
          errorCode: 'weird_new_code',
          rawMessage: "No such PaymentMethod: 'pm_123'",
          lang: 'cs');
      expect(info.message, isNot(contains('pm_123')));
      expect(info.title, PaymentErrorMapper.text('cs', 'cardDeclinedTitle'));
      final unknownCard = PaymentErrorMapper.fromStripeException(
          _se(type: 'card_error', localized: 'Your card was declined (device locale)'), 'de');
      expect(unknownCard.message, isNot(contains('device locale')));
    });

    test('error without card code = uncertain, never "nothing charged"', () {
      final info = PaymentErrorMapper.fromStripeException(_se(), 'cs');
      expect(info.needsVerification, isTrue);
      expect(info.message, isNot(contains('nestrhli')));
      final unexpected = PaymentErrorMapper.fromEdge(
          errorCode: 'payment_intent_unexpected_state', lang: 'en');
      expect(unexpected.needsVerification, isTrue);
    });

    test('cancel is not an error', () {
      final info = PaymentErrorMapper.fromStripeException(_se(code: FailureCode.Canceled), 'cs');
      expect(info.userCancelled, isTrue);
    });

    test('wallet failure does not send the customer back to the wallet', () {
      final info = PaymentErrorMapper.fromStripeException(
          _se(decline: 'insufficient_funds', type: 'card_error'), 'cs',
          wallet: true);
      expect(info.message, isNot(contains('Google Pay')));
      expect(info.message, isNot(contains('Apple Pay')));
    });

    test('Czech mapper texts use informal address (tykání)', () {
      for (final k in ['fundsBody', 'networkBody', 'authExpiredBody', 'genericBody', 'bankBlockBody']) {
        final s = PaymentErrorMapper.text('cs', k);
        expect(s, isNot(contains('Zkuste')), reason: k);
        expect(s, isNot(contains('Vaše')), reason: k);
      }
    });
  });

  group('PaymentRefusals.resolve', () {
    test('lost response after saved-card charge → verify, not retry', () {
      final r = PaymentResult.error('timeout', code: PaymentErrorCode.timeout, uncertain: true);
      final p = PaymentRefusals.resolve('cs', r, PayFlow.booking, amount: 1500);
      expect(p.action, PayAction.verify);
      expect(p.message, isNot(contains('nestrhli')));
    });

    test('plain network error (nothing sent) → retry, counts as attempt', () {
      final r = PaymentResult.error('network', code: PaymentErrorCode.networkError);
      final p = PaymentRefusals.resolve('en', r, PayFlow.booking, amount: 1500);
      expect(p.action, PayAction.retry);
      expect(p.countsAsAttempt, isTrue);
    });

    test('"already paid" without code (live server text) → success for a booking', () {
      final p = PaymentRefusals.resolve('de', _refused('Tato rezervace je již zaplacena.'),
          PayFlow.resume, amount: 1500);
      expect(p.action, PayAction.success);
    });

    test('"already paid" is never success for an edit surcharge', () {
      final p = PaymentRefusals.resolve('cs', _refused('Tato rezervace je již zaplacena.'),
          PayFlow.edit, amount: 300);
      expect(p.action, isNot(PayAction.success));
    });

    test('amount_mismatch with server_total → pay the server price', () {
      final p = PaymentRefusals.resolve(
          'cs', _refused('Cena rezervace je 1890 Kč.', code: 'amount_mismatch', total: 1890),
          PayFlow.booking, amount: 1700);
      expect(p.action, PayAction.priceChanged);
      expect(p.serverTotal, 1890);
      expect(p.countsAsAttempt, isFalse);
    });

    test('amount_mismatch on an edit → reload the edit', () {
      final p = PaymentRefusals.resolve(
          'en', _refused('x', code: 'amount_mismatch', total: 450), PayFlow.edit, amount: 400);
      expect(p.action, PayAction.reloadEdit);
    });

    test('0 Kč booking rejected with a price in the text → pay the remainder', () {
      final p = PaymentRefusals.resolve(
          'cs',
          _refused('Částka neodpovídá ceně rezervace (240 Kč). Obnovte stránku a zkuste znovu.',
              status: 400),
          PayFlow.booking,
          amount: 0);
      expect(p.action, PayAction.priceChanged);
      expect(p.serverTotal, 240);
    });

    test('Stripe minimum (500 from the server) → pay 15 Kč (D1), no raw English', () {
      final p = PaymentRefusals.resolve(
          'cs',
          _refused('Payment processing failed: Amount must be at least 15.00 czk', status: 500),
          PayFlow.edit,
          amount: 9);
      expect(p.action, PayAction.payMin);
      expect(p.serverTotal, 9);
      expect(p.message, isNot(contains('Amount must')));
      expect(p.message, contains('15'));
    });

    test('shop order gone → back to cart', () {
      final p = PaymentRefusals.resolve(
          'pl', _refused('Objednávka nenalezena.', code: 'order_not_found', status: 404),
          PayFlow.shop, amount: 500);
      expect(p.action, PayAction.toCart);
    });

    test('unknown refusal → retry, translated, no server text, no contact (D5)', () {
      final p = PaymentRefusals.resolve('uk', _refused('Neznámá chyba XYZ', code: 'weird'),
          PayFlow.booking, amount: 100);
      expect(p.action, PayAction.retry);
      expect(p.message, isNot(contains('XYZ')));
      expect(p.message, isNot(contains('@')));
    });
  });

  group('promo reasons', () {
    test('Czech RPC texts map to specific reasons', () {
      expect(promoReasonKey({'valid': false, 'error': 'Kód vypršel'}), 'psCodeExpired');
      expect(promoReasonKey({'valid': false, 'error': 'Kód ještě není platný'}), 'psCodeNotYet');
      expect(promoReasonKey({'valid': false, 'error': 'Kód byl vyčerpán'}), 'psCodeUsedUp');
      expect(promoReasonKey({'valid': false, 'error': 'Kód neexistuje nebo není aktivní'}), isNull);
      expect(promoReasonKey({'valid': false, 'rate_limited': true}), 'psCodeRateLimited');
    });

    test('Slevomat codes', () {
      expect(slevomatReasonKey({'valid': false, 'slevomat_error_code': 1105}), 'psVoucherRedeemed');
      expect(slevomatReasonKey({'valid': false, 'status': 'cancelled'}), 'psVoucherCancelled');
      expect(slevomatReasonKey({'valid': false, 'slevomat_error_code': 1103}), isNull);
      expect(slevomatReasonKey({'valid': false, 'error': 'Voucher se nepodařilo ověřit'}),
          'pdSlevomatUnverified');
    });
  });

  test('every ps* key exists in all 8 languages with the same placeholders', () {
    final cs = translations['cs']!;
    final keys = cs.keys.where((k) => k.startsWith('ps')).toList();
    expect(keys.length, greaterThan(100));
    final ph = RegExp(r'\{\w+\}');
    for (final lang in _langs) {
      final m = translations[lang]!;
      for (final k in keys) {
        expect(m[k], isNotNull, reason: '$lang.$k');
        expect(ph.allMatches(m[k]!).map((e) => e[0]).toSet(),
            ph.allMatches(cs[k]!).map((e) => e[0]).toSet(),
            reason: '$lang.$k placeholders');
      }
    }
  });
}
