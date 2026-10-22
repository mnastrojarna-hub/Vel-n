// Platby D1–D6 — opravy po kontrole (2026-10-16): dorovnání na 15 Kč i u
// „Cena se změnila", přesné texty výměny motorky, předchozí zaplacená úprava,
// výpadek spojení / serveru nejsou pokusy kartou, PSČ / „neopakovat",
// rezervace začínající dnes, konečné stavy dokončení, chyby BEZ kontaktu.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/friendly_error.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_44_payfix.dart';
import 'package:motogo_app/features/payment/paid_change_outcomes.dart';
import 'package:motogo_app/features/payment/payment_error_mapper.dart';
import 'package:motogo_app/features/payment/payment_refusals.dart';
import 'package:motogo_app/features/payment/stripe_service.dart';
import 'package:motogo_app/features/reservations/booking_restore.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

final _contact = RegExp(
    r'@|\+420|774 ?256|napiš(te)? nám|napsat nám|ozveme|ozve se|zavolej|write to us|get in touch|contact us|call us|'
    r'schreib uns|ruf uns|melden wir uns|escríbenos|llámanos|te contactaremos|écris-nous|appelle-nous|'
    r'nous te contacterons|stuur ons|bel ons|nemen we contact|napisz do nas|zadzwoń|odezwiemy|напиши нам|зателефонуй|зв.яжемося',
    caseSensitive: false);

PaymentResult _ref(String code, {double? total, int status = 409, bool previous = false}) =>
    PaymentResult.error('server text',
        code: PaymentErrorCode.serverError,
        serverCode: code,
        serverTotal: total,
        httpStatus: status,
        previousChange: previous);

void main() {
  group('D1: new price below the card minimum', () {
    test('7 Kč left after a voucher → „Zaplatit 15 Kč" with the rounding explained', () {
      for (final code in ['free_mismatch', 'amount_mismatch']) {
        final p = PaymentRefusals.resolve('cs', _ref(code, total: 7), PayFlow.booking, amount: 0);
        expect(p.action, PayAction.payMin, reason: code);
        expect(p.serverTotal, 7);
        expect(p.message, contains('15 Kč'));
        expect(p.message, contains('8 Kč'));
      }
    });

    test('≤ 1 Kč left → confirm without payment (waiver note), never „Zaplatit 1 Kč"', () {
      final p = PaymentRefusals.resolve('cs', _ref('free_mismatch', total: 0.6), PayFlow.booking, amount: 0);
      expect(p.action, PayAction.priceChanged);
      expect(p.serverTotal, 0.6);
      expect(p.message, PaymentErrorMapper.text('cs', 'pdWaiveNote').replaceAll('{amount}', '0,60 Kč'));
    });

    test('≥ 15 Kč unchanged (pay the new price)', () {
      final p = PaymentRefusals.resolve('cs', _ref('amount_mismatch', total: 1890), PayFlow.resume, amount: 1500);
      expect(p.action, PayAction.priceChanged);
      expect(p.serverTotal, 1890);
    });
  });

  group('D5: refusal texts', () {
    test('swap codes: precise text in 8 languages, nothing charged, no contact', () {
      for (final lang in _langs) {
        PaymentRefusals.swapCodes.forEach((code, key) {
          final s = PaymentErrorMapper.text(lang, key);
          expect(s, isNot(key), reason: '$lang/$code untranslated');
          expect(_contact.hasMatch(s), isFalse, reason: '$lang/$code');
          if (lang == 'cs') expect(s, contains('Nic jsme nestrhli'), reason: code);
        });
      }
      expect(PaymentRefusals.resolve('cs', _ref('new_moto_unavailable'), PayFlow.swap, amount: 15).message,
          PaymentErrorMapper.text('cs', 'pdSwapUnavailable'));
      expect(PaymentRefusals.resolve('cs', _ref('wrong_status'), PayFlow.swap, amount: 15).message,
          PaymentErrorMapper.text('cs', 'pdSwapWrongStatus'));
    });

    test('previous paid change: new change was NOT paid; stale = own earlier change', () {
      final p = PaymentRefusals.resolve('cs', _ref('payment_in_progress', previous: true), PayFlow.edit, amount: 300);
      expect(p.action, PayAction.reloadEdit);
      expect(p.message, PaymentErrorMapper.text('cs', 'pdPrevChangeBody'));
      final s = PaymentRefusals.resolve('cs', _ref('stale_booking', previous: true), PayFlow.swap, amount: 300);
      expect(s.message, PaymentErrorMapper.text('cs', 'pdPrevAppliedBody'));
      expect(PaymentRefusals.resolve('cs', _ref('stale_booking'), PayFlow.edit, amount: 300).message,
          PaymentErrorMapper.text('cs', 'refStale'));
    });

    test('validation_unavailable on a booking payment is not about an edit', () {
      final b = PaymentRefusals.resolve('cs', _ref('validation_unavailable', status: 503), PayFlow.resume, amount: 1);
      expect(b.message, PaymentErrorMapper.text('cs', 'psServerDownBody'));
      expect(b.action, PayAction.retry);
      expect(PaymentRefusals.resolve('cs', _ref('validation_unavailable'), PayFlow.edit, amount: 1).message,
          PaymentErrorMapper.text('cs', 'refValidationUnavailable'));
    });

    test('offline / timeout / 5xx are not card attempts', () {
      for (final c in [PaymentErrorCode.networkError, PaymentErrorCode.timeout]) {
        expect(PaymentRefusals.resolve('cs', PaymentResult.error('x', code: c), PayFlow.booking, amount: 100).countsAsAttempt,
            isFalse);
      }
      expect(PaymentRefusals.resolve('cs', _ref('weird', status: 502), PayFlow.booking, amount: 100).countsAsAttempt, isFalse);
      expect(PaymentRefusals.resolve('cs', _ref('weird', status: 400), PayFlow.booking, amount: 100).countsAsAttempt, isTrue);
    });
  });

  group('D5: Stripe codes', () {
    test('gateway / zip / wallet timeout / do-not-try-again', () {
      for (final lang in _langs) {
        String title({String? d, String? c}) => PaymentErrorMapper.fromEdge(declineCode: d, errorCode: c, lang: lang).title;
        expect(title(c: 'rate_limit'), PaymentErrorMapper.text(lang, 'pdGatewayTitle'));
        expect(title(c: 'api_connection_error'), PaymentErrorMapper.text(lang, 'pdGatewayTitle'));
        expect(title(d: 'incorrect_zip'), PaymentErrorMapper.text(lang, 'pdZipTitle'));
        expect(title(c: 'postal_code_invalid'), PaymentErrorMapper.text(lang, 'pdZipTitle'));
        expect(title(c: 'payment_method_provider_timeout'), PaymentErrorMapper.text(lang, 'walletFailedTitle'));
        final n = PaymentErrorMapper.fromEdge(declineCode: 'do_not_try_again', lang: lang);
        expect(n.message, PaymentErrorMapper.text(lang, 'pdDoNotRetryBody'));
        expect(n.cause, 'do_not_try_again');
      }
    });
  });

  group('restore (D3)', () {
    test('booking starting today has its own text', () {
      for (final lang in _langs) {
        final tr = AppTranslations(lang);
        final today = restoreRefusalText(tr, const RestoreRefused('date_passed', reason: 'today'));
        expect(today, isNot(restoreRefusalText(tr, const RestoreRefused('date_passed'))));
        expect(today, tr.tr('pdRestoreStartsToday'));
        expect(_contact.hasMatch(today), isFalse);
      }
    });
  });

  group('D6: final states of a paid change', () {
    test('every terminal reason has a precise text without leftovers or contact', () {
      const reasons = ['other_account', 'gone', 'refunded', 'stale_payment', 'expired', 'new_moto_unavailable', 'x'];
      for (final lang in _langs) {
        final tr = AppTranslations(lang);
        for (final r in reasons) {
          for (final refund in ['auto', 'staff', 'none']) {
            final s = paidChangeFailureText(tr, reason: r, refund: refund, amount: 15);
            expect(s, isNot(contains('{')), reason: '$lang/$r');
            expect(s, isNot(startsWith('pd')), reason: '$lang/$r');
            expect(_contact.hasMatch(s), isFalse, reason: '$lang/$r');
          }
        }
        expect(paidChangeFailureText(tr, reason: 'other_account', refund: 'none', amount: 15),
            tr.tr('pdFailForeign'));
      }
    });
  });

  group('no contact in generic error views (contact: false)', () {
    test('FriendlyError body and hint for every kind', () {
      for (final lang in _langs) {
        final tr = AppTranslations(lang);
        for (final k in FriendlyKind.values) {
          final fe = FriendlyError(k);
          for (final s in [fe.body(tr, contact: false), fe.hint(tr, contact: false), fe.reason(tr), fe.title(tr)]) {
            expect(s.trim(), isNotEmpty, reason: '$lang/$k');
            expect(s.startsWith('eo'), isFalse, reason: '$lang/$k untranslated: $s');
            expect(_contact.hasMatch(s), isFalse, reason: '$lang/$k: $s');
          }
        }
      }
    });
  });

  test('i18n ext_44: 8 languages, same keys and placeholders, registered, no contact', () {
    final cs = translationsExt44Payfix['cs']!;
    final ph = RegExp(r'\{\w+\}');
    for (final lang in _langs) {
      final m = translationsExt44Payfix[lang]!;
      expect(m.keys.toSet(), cs.keys.toSet(), reason: lang);
      for (final k in cs.keys) {
        expect(m[k]!.trim(), isNotEmpty, reason: '$lang.$k');
        expect(ph.allMatches(m[k]!).map((e) => e[0]).toSet(), ph.allMatches(cs[k]!).map((e) => e[0]).toSet(),
            reason: '$lang.$k placeholders');
        expect(_contact.hasMatch(m[k]!), isFalse, reason: '$lang.$k');
        expect(translations[lang]![k], m[k], reason: '$lang.$k registered');
      }
    }
  });
}
