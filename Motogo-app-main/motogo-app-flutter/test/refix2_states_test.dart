// Chybové stavy — 2. kolo ověření (2026-10-16): druh platby ve značce
// (doplatek úpravy ≠ zaplacená rezervace), co prokazatelně neodešlo vs. co
// mohlo strhnout kartu, výpadek sítě při obnově přihlášení ≠ odhlášení,
// poloha s vysvětlením místo tichého otevření Nastavení, texty v 8 jazycích.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_41_refix2.dart';
import 'package:motogo_app/core/native/gps_service.dart';
import 'package:motogo_app/core/payment_pending_marker.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';
import 'package:motogo_app/features/payment/net_error.dart';
import 'package:motogo_app/features/payment/payment_verify.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthApiException, AuthException, AuthRetryableFetchException;

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
const _key = 'mg_payment_submitted_v2';

void main() {
  group('PaymentPendingMarker kind', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('edit surcharge keeps kind + expected total across the attempt', () async {
      await PaymentPendingMarker.set('b1',
          fresh: true, kind: PaymentMarkerKind.edit, expectedTotal: 4200);
      // Další zápisy téhož pokusu (3DS intent, ověřování) druh nezahodí.
      await PaymentPendingMarker.set('b1', clientSecret: 'cs_1');
      final m = await PaymentPendingMarker.get('b1');
      expect(m!.kind, PaymentMarkerKind.edit);
      expect(m.expectedTotal, 4200);
      expect(m.clientSecretCurrent, isTrue);
      final all = await PaymentPendingMarker.pendingMarkers();
      expect(all.single.kind, PaymentMarkerKind.edit);
    });

    test('marker without kind is a booking payment', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode({'b2': {'at': now, 'att': now}}),
      });
      expect((await PaymentPendingMarker.get('b2'))!.kind, PaymentMarkerKind.booking);
    });

    test('swap surcharge without a known intent stays pending (no false success)',
        () async {
      await PaymentPendingMarker.set('b3', fresh: true, kind: PaymentMarkerKind.swap);
      final st = await verifyPayment(bookingId: 'b3', intentOnly: true);
      expect(st, VerifyState.pending);
      // Značka zůstává → druhý doplatek se nespustí (blockIfSurchargePending).
      expect(await PaymentPendingMarker.isPending('b3'), isTrue);
    });
  });

  group('request never sent vs. maybe charged', () {
    test('DNS / unreachable / refused → nothing left the phone', () {
      expect(requestNeverSent(ClientException(
          "SocketException: Failed host lookup: 'x.supabase.co' (OS Error: No address associated with hostname, errno = 7)")), isTrue);
      expect(requestNeverSent(const SocketException('Network is unreachable')), isTrue);
      expect(requestNeverSent(ClientException('Connection refused')), isTrue);
    });

    test('timeout / reset / closed after send → uncertain', () {
      expect(requestNeverSent(TimeoutException('t')), isFalse);
      expect(requestNeverSent(ClientException('Connection reset by peer')), isFalse);
      expect(requestNeverSent(ClientException(
          'Connection closed before full header was received')), isFalse);
    });
  });

  group('session refresh failure', () {
    test('network-ish failures never sign the customer out', () {
      expect(authRefreshNetworkFailure(AuthRetryableFetchException(message: 'x')), isTrue);
      expect(authRefreshNetworkFailure(TimeoutException('t')), isTrue);
      expect(authRefreshNetworkFailure(const SocketException('Failed host lookup')), isTrue);
      expect(authRefreshNetworkFailure(const FormatException('html')), isTrue);
    });

    test('a refused refresh token is a real sign-out', () {
      expect(
          authRefreshNetworkFailure(AuthApiException('Invalid Refresh Token',
              statusCode: '400', code: 'refresh_token_not_found')),
          isFalse);
      expect(authRefreshNetworkFailure(AuthException('session missing')), isFalse);
    });
  });

  group('location explanation (never opens Settings by itself)', () {
    Future<void> open(WidgetTester tester, GpsStatus st) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => explainLocation(ctx, st),
              child: const Text('GO'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();
    }

    testWidgets('location off → why + Open settings button', (tester) async {
      await open(tester, GpsStatus.serviceOff);
      expect(find.text(translations['en']!['eoLocOffTitle']!), findsOneWidget);
      expect(find.text(translations['en']!['eoOpenSettings']!), findsOneWidget);
      expect(find.text(translations['en']!['eoClose']!), findsOneWidget);
    });

    testWidgets('no GPS fix → explanation without a settings button', (tester) async {
      await open(tester, GpsStatus.noFix);
      expect(find.text(translations['en']!['fxLocNoFixTitle']!), findsOneWidget);
      expect(find.text(translations['en']!['eoOpenSettings']!), findsNothing);
      await tester.tap(find.text(translations['en']!['eoClose']!));
      await tester.pumpAndSettle();
      expect(find.text(translations['en']!['fxLocNoFixTitle']!), findsNothing);
    });
  });

  test('every new fx* text exists in all 8 languages (Czech tykání)', () {
    final keys = translationsExt41Refix2['cs']!.keys;
    expect(keys, isNotEmpty);
    for (final lang in _langs) {
      for (final k in keys) {
        final v = translations[lang]?[k];
        expect(v, isNotNull, reason: '$lang/$k');
        expect(v!.trim(), isNotEmpty, reason: '$lang/$k');
      }
    }
    for (final k in keys) {
      expect(translations['cs']![k],
          isNot(matches(RegExp(r'\b(Zkuste|Napište|Vyberte|vám|Vaše|Vám)\b'))));
    }
  });
}
