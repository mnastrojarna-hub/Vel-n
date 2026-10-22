// Chybové stavy — 3. kolo (2026-10-16): stržení uložené karty bez kódu =
// ověřit (nikdy „nic nestrženo"), detail motorky bez dat má cestu zpět,
// chyby přihlášení ≠ texty registrace (bez syrového textu, tykání), průběh
// s „Zrušit" na slabém signálu, texty v 8 jazycích.
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_42_refix3_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_42_refix3_b.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';
import 'package:motogo_app/core/widgets/state_views.dart' show MgBackArrow;
import 'package:motogo_app/features/auth/auth_error_mapper.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/payment/payment_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException, AuthException;

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

void main() {
  group('saved-card charge without Stripe code', () {
    test('no code + no intent status = uncertain (verify), never "nothing charged"', () {
      for (final lang in _langs) {
        final info = PaymentErrorMapper.fromEdge(lang: lang);
        expect(info.needsVerification, isTrue, reason: lang);
        expect(info.message, isNot(PaymentErrorMapper.generic(lang).message), reason: lang);
      }
    });

    test('unknown intent status is also uncertain', () {
      final info = PaymentErrorMapper.fromEdge(intentStatus: 'requires_capture', lang: 'cs');
      expect(info.needsVerification, isTrue);
    });

    test('PI that provably did not charge keeps the plain retry text', () {
      for (final st in ['requires_payment_method', 'canceled']) {
        final info = PaymentErrorMapper.fromEdge(intentStatus: st, lang: 'cs');
        expect(info.needsVerification, isFalse, reason: st);
        expect(info.message, PaymentErrorMapper.generic('cs').message);
      }
    });

    test('real decline still maps to the bank text (no verification)', () {
      final info = PaymentErrorMapper.fromEdge(errorCode: 'card_declined', lang: 'en');
      expect(info.needsVerification, isFalse);
      expect(info.cause, isNull);
    });
  });

  group('AuthErrorMapper sign-in vs sign-up', () {
    test('offline sign-in does not talk about an account not created', () {
      for (final lang in _langs) {
        final up = AuthErrorMapper.signUp(const SocketException('x'), lang);
        final inn = AuthErrorMapper.signIn(const SocketException('x'), lang);
        expect(inn.code, 'network');
        expect(inn.message, isNot(up.message), reason: lang);
        expect(inn.message, translations[lang]!['r3AuthNetBodyIn'], reason: lang);
      }
      expect(AuthErrorMapper.signIn(const SocketException('x'), 'cs').message,
          isNot(contains('nevznikl')));
    });

    test('server error / rate limit on sign-in use sign-in texts', () {
      final server = AuthErrorMapper.signIn(
          const AuthApiException('Database error', statusCode: '500'), 'cs');
      expect(server.code, 'server_error');
      expect(server.message, isNot(contains('založit')));
      final rate = AuthErrorMapper.signIn(
          const AuthApiException('Too many requests', statusCode: '429'), 'cs');
      expect(rate.code, 'rate_limit');
      expect(rate.message, isNot(contains('registr')));
      final rateUp = AuthErrorMapper.signUp(
          const AuthApiException('Too many requests', statusCode: '429'), 'cs');
      expect(rateUp.message, contains('registraci'));
    });

    test('unknown error never shows the raw exception text', () {
      for (final lang in _langs) {
        final info = AuthErrorMapper.signIn(
            const AuthException('weird_internal_error: pq: relation xyz'), lang);
        expect(info.code, 'unknown');
        expect(info.message, isNot(contains('weird_internal_error')), reason: lang);
        expect(info.message, isNot(endsWith(':')), reason: lang);
      }
    });

    test('Czech auth texts use informal address (tykání)', () {
      final infos = [
        AuthErrorMapper.emailTaken('cs'),
        for (final e in <Object>[
          const SocketException('x'),
          const AuthApiException('Database error', statusCode: '500'),
          const AuthApiException('rate limit', statusCode: '429'),
          const AuthException('weak_password'),
          const AuthException('invalid email'),
          const AuthException('invalid login credentials'),
          const AuthException('email not confirmed'),
          const AuthException('signups not allowed'),
          const AuthException('???'),
        ]) ...[AuthErrorMapper.signIn(e, 'cs'), AuthErrorMapper.signUp(e, 'cs')],
      ];
      final formal = RegExp(
          r'\b(Zkontrolujte|Zkuste|Přihlaste|ozvěte|Zvolte|Otevřete|Počkejte|Podívejte|napište|můžete|jste|Máte)\b');
      for (final i in infos) {
        expect(formal.hasMatch(i.message), isFalse, reason: i.message);
      }
    });
  });

  group('r3 texts', () {
    test('every r3 key exists in all 8 languages', () {
      final keys = translationsExt42Refix3A['cs']!.keys.toSet();
      for (final lang in _langs) {
        final m = translationsExt42Refix3A[lang] ?? translationsExt42Refix3B[lang]!;
        expect(m.keys.toSet(), keys, reason: lang);
        for (final k in keys) {
          expect(m[k]!.trim(), isNotEmpty, reason: '$lang.$k');
          expect(translations[lang]![k], m[k], reason: 'merged $lang.$k');
        }
      }
    });
  });

  group('MgProgress cancel', () {
    testWidgets('no way out before the limit, then Cancel ends the wait', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
      ));
      final p = MgProgress.show(ctx, 'Working', cancelAfter: const Duration(seconds: 20));
      final never = Completer<int>();
      Object? result;
      unawaited(p.guard(never.future).then((v) => result = v, onError: (Object e) => result = e));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Working'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(find.byType(TextButton), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(find.text('Working'), findsNothing);
      expect(p.cancelled, isTrue);
      expect(result, isA<MgCancelled>());
      // Pozdní výsledek už nic nezmění.
      never.complete(1);
      await tester.pump();
      expect(result, isA<MgCancelled>());
    });

    testWidgets('system back cancels a cancellable progress', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
      ));
      final p = MgProgress.show(ctx, 'Working', cancelAfter: const Duration(seconds: 15));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Android Zpět / iOS gesto = „Zrušit" (i před zobrazením tlačítka).
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(p.cancelled, isTrue);
      expect(find.text('Working'), findsNothing);
    });

    testWidgets('non-cancellable progress (SOS) keeps blocking back', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
      ));
      final p = MgProgress.show(ctx, 'Sending');
      await tester.pump(const Duration(seconds: 30));
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(p.cancelled, isFalse);
      expect(find.text('Sending'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      p.close();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('Moto detail without data', () {
    Widget app(List<Motorcycle> motos) => ProviderScope(
          overrides: [
            motorcyclesProvider.overrideWith((ref) => Stream.value(motos)),
            bookedDatesProvider.overrideWith((ref, id) async => const []),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MotoDetailPage(motoId: 'gone', showBackButton: true)),
          ),
        );

    testWidgets('bike no longer offered: reason + pick another + visible back', (tester) async {
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();
      // Výchozí jazyk testu = en.
      expect(find.text(translations['en']!['r3MotoGoneTitle']!), findsOneWidget);
      expect(find.text(translations['en']!['r3PickOtherMoto']!), findsOneWidget);
      // Šipka zpět je vidět i bez dat (dřív jen holý text bez akce).
      expect(find.byType(MgBackArrow), findsOneWidget);
    });
  });
}
