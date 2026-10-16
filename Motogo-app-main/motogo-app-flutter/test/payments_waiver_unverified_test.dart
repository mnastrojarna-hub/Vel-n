// Platby D1/D5 — oprava po kontrole (2026-10-16):
//  • zbytek do 1 Kč, který server nedokázal ověřit k odpuštění (`below_minimum`
//    + `waiver_unverified`), se platí 15 Kč — „Zaplatit 15 Kč" nesmí znovu
//    poslat 0 Kč (dřív nekonečná smyčka odmítnutí),
//  • storno konceptu rezervace z FAB: hláška bez kontaktu (D5).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/friendly_error.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_45_payments.dart';
import 'package:motogo_app/features/payment/card_minimum.dart';
import 'package:motogo_app/features/payment/payment_refusals.dart';
import 'package:motogo_app/features/payment/stripe_service.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

final _contact = RegExp(
    r'@|\+420|774 ?256|napiš(te)? nám|napsat nám|ozveme|ozve se|write to us|get in touch|contact us|'
    r'schreib uns|melden wir uns|escríbenos|te contactaremos|écris-nous|nous te contacterons|'
    r'stuur ons|nemen we contact|napisz do nas|odezwiemy|напиши нам|зв.яжемося',
    caseSensitive: false);

/// Odpověď process-payment na odpuštění, které server neověřil (index.ts).
PaymentResult _unverified(num due) => PaymentResult.refusal({
      'success': false,
      'error': 'Zbývá $due Kč. Tuhle částku teď nejde odpustit …',
      'code': 'below_minimum',
      'due': due,
      'min': 15,
      'charge': 15,
      'update_required': false,
      'waiver_unverified': true,
    }, httpStatus: 400);

void main() {
  group('waiver_unverified (D1)', () {
    test('refusal is parsed with the flag and the server due', () {
      final r = _unverified(0.6);
      expect(r.type, PaymentResultType.error);
      expect(r.serverCode, 'below_minimum');
      expect(r.waiverUnverified, isTrue);
      expect(r.serverDue, 0.6);
      expect(r.uncertain, isFalse);
      expect(PaymentResult.refusal({'code': 'below_minimum', 'due': 7.5}).waiverUnverified, isFalse);
    });

    test('below_minimum 0,60 Kč + waiver_unverified → request of 15 Kč, never 0', () {
      for (final flow in PayFlow.values) {
        final p = PaymentRefusals.resolve('cs', _unverified(0.6), flow, amount: 0.6);
        expect(p.action, PayAction.payMin, reason: '$flow');
        expect(p.forceMinCharge, isTrue, reason: '$flow');
        // Přesně to, co obrazovka po „Zaplatit 15 Kč" pošle serveru.
        final cc = cardCharge(p.serverTotal ?? 0.6, forceMin: p.forceMinCharge);
        expect(cc.charge, 15, reason: '$flow');
        expect(cc.isWaive, isFalse, reason: '$flow');
        expect(cc.rounding, closeTo(14.4, 0.001), reason: '$flow');
      }
      // Bez vynucení by se poslalo znovu odpuštění (0 Kč) → smyčka.
      expect(cardCharge(0.6).charge, 0);
    });

    test('payMin with due ≤ 1 forces 15 Kč even without the flag; 7,50 Kč stays a normal top-up', () {
      final old = PaymentRefusals.belowMinimum('cs', 0.6);
      expect(old.forceMinCharge, isTrue);
      expect(cardCharge(0.6, forceMin: old.forceMinCharge).charge, 15);
      final mid = PaymentRefusals.belowMinimum('cs', 7.5);
      expect(mid.forceMinCharge, isFalse);
      expect(cardCharge(7.5, forceMin: mid.forceMinCharge).charge, 15);
      expect(cardCharge(20, forceMin: true).charge, 20);
      expect(cardCharge(0, forceMin: true).kind, CardChargeKind.free);
    });

    test('text says why it is not waived, what to pay and that nothing was charged — 8 languages', () {
      for (final lang in _langs) {
        final p = PaymentRefusals.resolve(lang, _unverified(0.6), PayFlow.edit, amount: 0.6);
        final all = '${p.title} ${p.message}';
        expect(all.contains('server text'), isFalse, reason: lang);
        expect(all.contains('Tuhle částku'), isFalse, reason: '$lang raw server text');
        expect(all.contains('{'), isFalse, reason: '$lang placeholder');
        expect(p.message.contains('0,60 Kč'), isTrue, reason: '$lang amount');
        expect(p.message.contains('14,40 Kč'), isTrue, reason: '$lang rounding');
        expect(p.message.contains('15'), isTrue, reason: '$lang minimum');
        expect(_contact.hasMatch(all), isFalse, reason: '$lang contact');
        expect(p.message, translationsExt45Payments[lang]!['pdWaiverUnverifiedBody']!
            .replaceAll('{amount}', '0,60 Kč')
            .replaceAll('{rounding}', '14,40 Kč'), reason: lang);
      }
    });
  });

  group('i18n ext_45', () {
    test('8 languages, same keys and placeholders, registered, no contact', () {
      final cs = translationsExt45Payments['cs']!;
      final ph = RegExp(r'\{\w+\}');
      for (final lang in _langs) {
        final m = translationsExt45Payments[lang]!;
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
  });

  group('FAB cancel of an unpaid booking (D5)', () {
    test('compose(contact: false) has no contact for server / unknown errors — 8 languages', () {
      for (final lang in _langs) {
        final tr = AppTranslations.of(lang);
        for (final kind in [FriendlyKind.server, FriendlyKind.unknown]) {
          final s = FriendlyError(kind).compose(tr, 'X', contact: false);
          expect(_contact.hasMatch(s), isFalse, reason: '$lang/$kind: $s');
          expect(s.startsWith('X – '), isTrue, reason: '$lang/$kind');
        }
      }
      // Výchozí chování (mimo platby) se nemění: chyba serveru nabízí kontakt.
      expect(_contact.hasMatch(FriendlyError(FriendlyKind.server).compose(AppTranslations.of('cs'), 'X')),
          isTrue);
    });

    test('every error snack in the booking / payment shell passes contact: false', () {
      const files = [
        'lib/core/shell_fabs.dart',
        'lib/core/shell_fabs_b.dart',
        'lib/core/shell_paid_listener.dart',
        'lib/core/app_shell.dart',
      ];
      var calls = 0;
      for (final f in files) {
        final file = File(f);
        if (!file.existsSync()) continue;
        final src = file.readAsStringSync();
        var i = src.indexOf('showErrorSnack(');
        while (i >= 0) {
          final end = src.indexOf(');', i);
          final call = src.substring(i, end < 0 ? src.length : end);
          calls++;
          expect(call.contains('contact: false'), isTrue, reason: '$f: $call');
          i = src.indexOf('showErrorSnack(', i + 1);
        }
      }
      expect(calls, greaterThan(0));
    });
  });
}
