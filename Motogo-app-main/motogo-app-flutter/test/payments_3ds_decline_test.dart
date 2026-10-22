// Zamítnutí PO 3D Secure (uložená karta, off-session SCA): zákazník musí
// slyšet pravý důvod (nedostatek prostředků, propadlá karta…), ne „dokonči
// ověření 3D Secure" — jinak ověřuje znovu a znovu až do limitu pokusů (D5).
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/payment/payment_error_mapper.dart';
import 'package:motogo_app/features/payment/stripe_service.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

StripeException _se({
  FailureCode code = FailureCode.Failed,
  String? stripeCode,
  String? decline,
  String? type,
}) =>
    StripeException(
      error: LocalizedErrorMessage(
        code: code,
        stripeErrorCode: stripeCode,
        declineCode: decline,
        type: type,
        message: 'Your card was declined (raw)',
        localizedMessage: 'Your card was declined (raw)',
      ),
    );

/// Hláška, kterou appka po 3DS ukáže (stejná logika jako _chargeSavedCard):
/// kód zamítnutí → mapper, jinak hláška o ověření.
PaymentErrorInfo? _declined(StripeException e, String lang) {
  final r = NextActionResult.fromException(e);
  final d = r.declineError;
  return d == null ? null : PaymentErrorMapper.fromStripeException(d, lang);
}

void main() {
  group('NextActionResult.fromException', () {
    test('cancel = not completed, no decline reason', () {
      final r = NextActionResult.fromException(
          _se(code: FailureCode.Canceled, stripeCode: 'card_declined', decline: 'insufficient_funds'));
      expect(r.outcome, NextActionOutcome.notCompleted);
      expect(r.declineError, isNull);
    });

    test('no code / connection or API error = unknown (verify, never "not charged")', () {
      expect(NextActionResult.fromException(_se()).outcome, NextActionOutcome.unknown);
      for (final c in ['api_connection_error', 'api_error', 'rate_limit', 'lock_timeout']) {
        final r = NextActionResult.fromException(_se(stripeCode: c));
        expect(r.outcome, NextActionOutcome.unknown, reason: c);
        expect(r.declineError, isNull, reason: c);
      }
      expect(NextActionResult.fromException(_se(type: 'api_connection_error', stripeCode: 'x')).outcome,
          NextActionOutcome.unknown);
    });

    test('3DS authentication failure keeps the 3D Secure message', () {
      for (final c in [
        'payment_intent_authentication_failure',
        'authentication_required',
        'setup_intent_authentication_failure',
      ]) {
        final r = NextActionResult.fromException(_se(stripeCode: c));
        expect(r.outcome, NextActionOutcome.failed, reason: c);
        expect(r.declineError, isNull, reason: c);
      }
      final r = NextActionResult.fromException(
          _se(stripeCode: 'card_declined', decline: 'authentication_required'));
      expect(r.outcome, NextActionOutcome.failed);
      expect(r.declineError, isNull);
    });

    test('status-only failure (no exception) has no decline reason', () {
      expect(const NextActionResult(NextActionOutcome.failed).declineError, isNull);
    });
  });

  group('decline after 3D Secure maps to the real reason', () {
    test('insufficient funds / expired / CVC / limit in every language', () {
      for (final lang in _langs) {
        final funds = _declined(_se(stripeCode: 'card_declined', decline: 'insufficient_funds'), lang)!;
        expect(funds.title, PaymentErrorMapper.text(lang, 'fundsTitle'), reason: lang);
        expect(funds.title, isNot(PaymentErrorMapper.text(lang, 'authTitle')), reason: lang);
        final exp = _declined(_se(stripeCode: 'expired_card', decline: 'expired_card'), lang)!;
        expect(exp.title, PaymentErrorMapper.text(lang, 'expiredTitle'), reason: lang);
        final exp2 = _declined(_se(stripeCode: 'expired_card'), lang)!;
        expect(exp2.title, PaymentErrorMapper.text(lang, 'expiredTitle'), reason: lang);
        final cvc = _declined(_se(stripeCode: 'incorrect_cvc'), lang)!;
        expect(cvc.title, PaymentErrorMapper.text(lang, 'cvcTitle'), reason: lang);
        final lim = _declined(_se(stripeCode: 'card_declined', decline: 'card_velocity_exceeded'), lang)!;
        expect(lim.title, PaymentErrorMapper.text(lang, 'limitTitle'), reason: lang);
        final dnh = _declined(_se(stripeCode: 'card_declined', decline: 'do_not_honor'), lang)!;
        expect(dnh.title, PaymentErrorMapper.text(lang, 'bankBlockTitle'), reason: lang);
        expect(dnh.message, isNot(contains('(raw)')), reason: lang);
      }
    });

    test('lost / stolen card gets the generic safe bank wording', () {
      for (final d in ['lost_card', 'stolen_card', 'pickup_card']) {
        final i = _declined(_se(stripeCode: 'card_declined', decline: d), 'cs')!;
        expect(i.title, PaymentErrorMapper.text('cs', 'bankBlockTitle'), reason: d);
        expect(i.message, PaymentErrorMapper.text('cs', 'bankBlockBody'), reason: d);
      }
    });

    test('actions: other card / below minimum / verify', () {
      expect(_declined(_se(stripeCode: 'card_declined', decline: 'do_not_try_again'), 'cs')!.cause,
          'do_not_try_again');
      expect(_declined(_se(stripeCode: 'resource_missing'), 'cs')!.cause, 'card_gone');
      expect(_declined(_se(stripeCode: 'amount_too_small'), 'cs')!.cause, 'amount_too_small');
      expect(_declined(_se(stripeCode: 'card_declined', decline: 'duplicate_transaction'), 'cs')!
          .needsVerification, isTrue);
      expect(_declined(_se(stripeCode: 'payment_intent_unexpected_state'), 'cs')!.needsVerification,
          isTrue);
    });

    test('unknown decline code = generic bank decline, not 3D Secure', () {
      final i = _declined(_se(stripeCode: 'card_declined', decline: 'brand_new_code'), 'en')!;
      expect(i.title, PaymentErrorMapper.text('en', 'cardDeclinedTitle'));
      expect(i.title, isNot(PaymentErrorMapper.text('en', 'authTitle')));
    });
  });
}
