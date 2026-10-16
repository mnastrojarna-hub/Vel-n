// Platby D1–D6 (2026-10-16): minimum karty 15 Kč (dorovnání / do 1 Kč se
// neúčtuje), kódy odmítnutí process-payment, Stripe kódy, obnovení
// rezervace, dokončení zaplacené změny — a ŽÁDNÉ kontakty v hláškách (D5).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_43_payments.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart' show pendingWindowStart;
import 'package:motogo_app/features/payment/card_minimum.dart';
import 'package:motogo_app/features/payment/paid_change_api.dart';
import 'package:motogo_app/features/payment/payment_error_mapper.dart';
import 'package:motogo_app/features/payment/payment_refusals.dart';
import 'package:motogo_app/features/payment/stripe_service.dart';
import 'package:motogo_app/features/reservations/booking_restore.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

PaymentResult _refused(String code, {double? total, double? due, String? detail, int status = 409}) =>
    PaymentResult.error('server text $code',
        code: PaymentErrorCode.serverError,
        serverCode: code,
        serverTotal: total,
        serverDue: due,
        detail: detail,
        httpStatus: status);

/// Naše kontakty / „napiš nám" v jakémkoli jazyce (D5: nikde v platbách).
final _contact = RegExp(
    r'@|\+420|774 ?256|napiš(te)? nám|napsat nám|ozveme|ozve se|write to us|get in touch|contact us|'
    r'schreib uns|melden wir uns|escríbenos|te contactaremos|écris-nous|nous te contacterons|'
    r'stuur ons|nemen we contact|napisz do nas|odezwiemy|напиши нам|зв.яжемося',
    caseSensitive: false);

void main() {
  group('cardCharge (D1/D2)', () {
    test('rule table', () {
      final cases = <num, (CardChargeKind, int, double)>{
        -5: (CardChargeKind.free, 0, 0),
        0: (CardChargeKind.free, 0, 0),
        0.4: (CardChargeKind.waive, 0, -0.4),
        1: (CardChargeKind.waive, 0, -1),
        1.01: (CardChargeKind.round, 15, 13.99),
        7.5: (CardChargeKind.round, 15, 7.5),
        14.6: (CardChargeKind.round, 15, 0.4),
        15: (CardChargeKind.normal, 15, 0),
        15.4: (CardChargeKind.normal, 15, 0),
        1234.5: (CardChargeKind.normal, 1235, 0),
      };
      cases.forEach((due, exp) {
        final c = cardCharge(due);
        expect(c.kind, exp.$1, reason: '$due kind');
        expect(c.charge, exp.$2, reason: '$due charge');
        expect(c.rounding, closeTo(exp.$3, 0.001), reason: '$due rounding');
      });
      expect(cardCharge(0.6).noCharge, isTrue);
      expect(cardCharge(7).noCharge, isFalse);
    });

    test('exact Kč formatting for small amounts', () {
      expect(kcExact(0.6), '0,60 Kč');
      expect(kcExact(15), '15 Kč');
      expect(kcExact(7.5), '7,50 Kč');
      expect(kcExact(-0.6), '−0,60 Kč');
    });

    test('attempt ids are unique and server-safe', () {
      final ids = {for (var i = 0; i < 200; i++) newAttemptId()};
      expect(ids.length, 200);
      for (final id in ids) {
        expect(RegExp(r'^[A-Za-z0-9-]{8,64}$').hasMatch(id), isTrue, reason: id);
      }
    });
  });

  group('PaymentRefusals — every process-payment code', () {
    final expected = <String, PayAction>{
      'already_paid': PayAction.success,
      'no_payment_needed': PayAction.success,
      'payment_in_progress': PayAction.pending,
      'duplicate_request': PayAction.verify,
      'below_minimum': PayAction.payMin,
      'rounding_unavailable': PayAction.retry,
      'booking_cancelled': PayAction.reservations,
      'voucher_unavailable': PayAction.editBooking,
      'auth_required': PayAction.signIn,
      'forbidden': PayAction.signIn,
      'amount_mismatch': PayAction.priceChanged,
      'free_mismatch': PayAction.priceChanged,
      'free_confirm_failed': PayAction.retry,
      'change_too_large': PayAction.reloadEdit,
      'change_not_applicable': PayAction.reloadEdit,
      'stripe_unavailable': PayAction.retry,
      'server_error': PayAction.retry,
      'invalid_type': PayAction.retry,
      'missing_booking_id': PayAction.retry,
      'missing_order_id': PayAction.retry,
      'invalid_amount': PayAction.retry,
      'delivery_fee_guard': PayAction.editAddress,
      'location_requires_route': PayAction.editAddress,
      'order_not_found': PayAction.toCart,
      'wrong_status': PayAction.reservations,
      'booking_not_found': PayAction.reservations,
      'stale_booking': PayAction.reloadEdit,
      'moto_unavailable': PayAction.reloadEdit,
      'active_pickup_time_locked': PayAction.reloadEdit,
      'trailer_staffed_only': PayAction.reloadEdit,
      'trailer_unavailable': PayAction.reloadEdit,
      'validation_unavailable': PayAction.retry,
      'trailer_check_unavailable': PayAction.retry,
      'not_found': PayAction.reloadEdit,
      'not_paid': PayAction.reloadEdit,
      'invalid_new_moto': PayAction.reloadEdit,
      'swap_date_out_of_range': PayAction.reloadEdit,
      'already_split': PayAction.reloadEdit,
      'license_insufficient': PayAction.reloadEdit,
      'new_moto_unavailable': PayAction.reloadEdit,
      'something_new': PayAction.retry,
    };
    test('action, translated text, no server text, no contact — 8 languages', () {
      for (final lang in _langs) {
        expected.forEach((code, action) {
          final p = PaymentRefusals.resolve(
              lang, _refused(code, total: 1890, due: 7, detail: 'MG-ABC'), PayFlow.booking,
              amount: 1500);
          expect(p.action, action, reason: '$lang/$code');
          expect(p.title.trim(), isNotEmpty, reason: '$lang/$code');
          expect(p.message, isNot(contains('server text')), reason: '$lang/$code');
          expect(p.message, isNot(matches(RegExp(r'^[a-zA-Z.]+$'))), reason: '$lang/$code untranslated');
          expect(_contact.hasMatch('${p.title} ${p.message}'), isFalse, reason: '$lang/$code contact');
        });
      }
    });

    test('below_minimum offers 15 Kč with the server due and the rounding', () {
      final p = PaymentRefusals.resolve('cs', _refused('below_minimum', due: 7), PayFlow.resume, amount: 7);
      expect(p.action, PayAction.payMin);
      expect(p.serverTotal, 7);
      expect(p.message, contains('7 Kč'));
      expect(p.message, contains('8 Kč'));
    });

    test('voucher code is shown; edit / shop flows get their own action', () {
      final v = PaymentRefusals.resolve('cs', _refused('voucher_unavailable', detail: 'MG-ABC'), PayFlow.resume, amount: 1);
      expect(v.message, contains('MG-ABC'));
      expect(v.action, PayAction.reservations);
      expect(PaymentRefusals.resolve('en', _refused('already_paid'), PayFlow.edit, amount: 100).action,
          PayAction.reloadEdit);
      expect(PaymentRefusals.resolve('en', _refused('amount_mismatch', total: 90), PayFlow.shop, amount: 80).action,
          PayAction.toCart);
      expect(PaymentRefusals.resolve('de', _refused('payment_in_progress'), PayFlow.swap, amount: 80).message,
          PaymentErrorMapper.text('de', 'psPendingBodyEdit'));
    });

    test('server errors do not burn card attempts, unknown codes do', () {
      expect(PaymentRefusals.resolve('cs', _refused('stripe_unavailable'), PayFlow.booking, amount: 100).countsAsAttempt, isFalse);
      expect(PaymentRefusals.resolve('cs', _refused('server_error', status: 500), PayFlow.booking, amount: 100).countsAsAttempt, isFalse);
      expect(PaymentRefusals.resolve('cs', _refused('weird_new'), PayFlow.booking, amount: 100).countsAsAttempt, isTrue);
    });
  });

  group('PaymentErrorMapper — Stripe codes (D5)', () {
    test('lost / stolen / pickup card = generic bank decline (nothing revealed)', () {
      for (final lang in _langs) {
        for (final d in ['lost_card', 'stolen_card', 'pickup_card']) {
          final i = PaymentErrorMapper.fromEdge(declineCode: d, lang: lang);
          expect(i.title, PaymentErrorMapper.text(lang, 'bankBlockTitle'), reason: '$lang/$d');
          expect(i.message, PaymentErrorMapper.text(lang, 'bankBlockBody'), reason: '$lang/$d');
        }
      }
    });

    test('specific codes map to specific texts', () {
      const map = {
        'insufficient_funds': 'fundsTitle',
        'expired_card': 'expiredTitle',
        'incorrect_cvc': 'cvcTitle',
        'incorrect_number': 'numberTitle',
        'card_not_supported': 'psNotSupportedTitle',
        'currency_not_supported': 'pdCurrencyTitle',
        'card_velocity_exceeded': 'limitTitle',
        'withdrawal_count_limit_exceeded': 'limitTitle',
        'processing_error': 'processingTitle',
        'try_again_later': 'processingTitle',
        'authentication_required': 'authTitle',
        'do_not_honor': 'bankBlockTitle',
        'generic_decline': 'cardDeclinedTitle',
        'card_declined': 'cardDeclinedTitle',
      };
      for (final lang in _langs) {
        map.forEach((code, title) {
          expect(PaymentErrorMapper.fromEdge(declineCode: code, lang: lang).title,
              PaymentErrorMapper.text(lang, title), reason: '$lang/$code');
        });
        expect(PaymentErrorMapper.fromEdge(errorCode: 'payment_method_provider_decline', lang: lang).title,
            PaymentErrorMapper.text(lang, 'pdWalletDeclinedTitle'));
        expect(PaymentErrorMapper.fromEdge(errorCode: 'payment_intent_payment_attempt_expired', lang: lang).title,
            PaymentErrorMapper.text(lang, 'pdAttemptExpiredTitle'));
        expect(PaymentErrorMapper.fromEdge(errorCode: 'amount_too_small', lang: lang).cause, 'amount_too_small');
      }
    });

    test('duplicate transaction = verify, never "pay again"', () {
      expect(PaymentErrorMapper.fromEdge(declineCode: 'duplicate_transaction', lang: 'cs').needsVerification, isTrue);
    });

    test('wallet errors keep raw codes out of the text', () {
      final w = PaymentErrorMapper.walletFailed('cs', rawCode: 'OR_BIBED_11');
      expect(w.message, isNot(contains('OR_BIBED')));
      expect(PaymentErrorMapper.wallet('en', rawCode: 'X_1').message, isNot(contains('X_1')));
    });
  });

  group('restore (D3)', () {
    test('every RPC error has a precise text without contact in 8 languages', () {
      const codes = [
        RestoreRefused('forbidden'), RestoreRefused('not_found'), RestoreRefused('not_cancelled'),
        RestoreRefused('not_restorable'), RestoreRefused('cancelled_by_staff'), RestoreRefused('date_passed'),
        RestoreRefused('restore_limit'), RestoreRefused('voucher_unavailable', discountCode: 'MG-1'),
        RestoreRefused('promo_unavailable', discountCode: 'JARO'), RestoreRefused('moto_unavailable'),
        RestoreRefused('moto_unavailable', reason: 'own_overlap'),
        RestoreRefused('moto_unavailable', reason: 'branch_closed'),
        RestoreRefused('moto_unavailable', reason: 'trailer'), RestoreRefused(restoreUpdatingCode),
        RestoreRefused('boom'),
      ];
      for (final lang in _langs) {
        final tr = AppTranslations(lang);
        final seen = <String>{};
        for (final c in codes) {
          final s = restoreRefusalText(tr, c);
          expect(s.startsWith('pd'), isFalse, reason: '$lang/${c.code} untranslated');
          expect(_contact.hasMatch(s), isFalse, reason: '$lang/${c.code}');
          seen.add(s);
        }
        expect(seen.length, codes.length, reason: '$lang: each case its own text');
        expect(restoreRefusalText(tr, codes[7]), contains('MG-1'));
      }
    });

    test('payment window counts from the restore', () {
      final w = pendingWindowStart('2026-10-16T08:00:00Z', '2026-10-16T09:30:00Z');
      expect(w, DateTime.parse('2026-10-16T09:30:00Z'));
      expect(pendingWindowStart('2026-10-16T08:00:00Z', null), DateTime.parse('2026-10-16T08:00:00Z'));
    });
  });

  group('complete_extension response (D6)', () {
    test('mapping', () {
      expect(CompleteResponse.fromHttp(200, {'success': true, 'state': 'applied'}).state, CompleteState.applied);
      expect(CompleteResponse.fromHttp(200, {'success': true, 'state': 'already_applied', 'new_booking_id': 'b2'}).newBookingId, 'b2');
      expect(CompleteResponse.fromHttp(200, {'success': true, 'state': 'client_apply'}).state, CompleteState.clientApply);
      expect(CompleteResponse.fromHttp(202, {'success': false, 'state': 'pending'}).state, CompleteState.pending);
      expect(CompleteResponse.fromHttp(503, {'success': false, 'state': 'retry'}).state, CompleteState.retry);
      expect(CompleteResponse.fromHttp(502, null).state, CompleteState.retry);
      expect(CompleteResponse.fromHttp(401, {'code': 'auth_required'}).state, CompleteState.retry);
      expect(CompleteResponse.fromHttp(200, {'success': false, 'state': 'not_paid'}).state, CompleteState.notPaid);
      final f = CompleteResponse.fromHttp(200,
          {'success': false, 'state': 'failed', 'reason': 'new_moto_unavailable', 'refund': 'staff', 'amount': 15});
      expect(f.state, CompleteState.failed);
      expect(f.reason, 'new_moto_unavailable');
      expect(f.refund, 'staff');
      expect(f.amount, 15);
    });

    test('PaymentIntent id from client secret', () {
      expect(piIdFromClientSecret('pi_3AbC_secret_xyz'), 'pi_3AbC');
      expect(piIdFromClientSecret('seti_1_secret_x'), isNull);
      expect(piIdFromClientSecret(null), isNull);
    });
  });

  group('i18n ext_43', () {
    test('8 languages, same keys, same placeholders, no contact', () {
      final cs = translationsExt43Payments['cs']!;
      final ph = RegExp(r'\{\w+\}');
      for (final lang in _langs) {
        final m = translationsExt43Payments[lang]!;
        expect(m.keys.toSet(), cs.keys.toSet(), reason: lang);
        for (final k in cs.keys) {
          expect(m[k]!.trim(), isNotEmpty, reason: '$lang.$k');
          expect(ph.allMatches(m[k]!).map((e) => e[0]).toSet(),
              ph.allMatches(cs[k]!).map((e) => e[0]).toSet(),
              reason: '$lang.$k placeholders');
          expect(_contact.hasMatch(m[k]!), isFalse, reason: '$lang.$k contact');
          expect(translations[lang]![k], m[k], reason: '$lang.$k registered');
        }
      }
    });

    test('no payment / booking / restore / edit / swap / shop screen shows a contact', () {
      const files = [
        'lib/features/payment',
        'lib/features/reservations/booking_restore.dart',
        'lib/features/reservations/reservation_edit_screen.dart',
        'lib/features/reservations/widgets/reservation_edit_states.dart',
        'lib/features/reservations/widgets/reservation_swap_section.dart',
        'lib/features/reservations/widgets/cancel_result_dialog.dart',
        'lib/features/reservations/widgets/paid_change_banner.dart',
        'lib/features/shop/shop_checkout_screen.dart',
        'lib/core/shell_paid_listener.dart',
        'lib/core/app_shell.dart',
      ];
      final keys = <String>{};
      final lit = RegExp(r"'([A-Za-z][A-Za-z0-9_.]{3,})'");
      for (final f in files) {
        final ents = FileSystemEntity.typeSync(f) == FileSystemEntityType.directory
            ? Directory(f).listSync(recursive: true).whereType<File>()
            : [if (File(f).existsSync()) File(f)];
        for (final file in ents) {
          if (!file.path.endsWith('.dart') || file.path.endsWith('payment_error_mapper.dart')) continue;
          for (final m in lit.allMatches(file.readAsStringSync())) {
            keys.add(m.group(1)!);
          }
        }
      }
      final cs = translations['cs']!;
      final used = keys.where(cs.containsKey).toList();
      expect(used.length, greaterThan(100));
      for (final lang in _langs) {
        for (final k in used) {
          final s = PaymentErrorMapper.text(lang, k);
          expect(_contact.hasMatch(s), isFalse, reason: '$lang.$k: $s');
        }
      }
    });
  });
}
