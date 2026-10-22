// Chybové stavy mimo platby (2026-10-16): každá chyba má srozumitelný text
// ve všech 8 jazycích (co / proč / jak), nikdy syrovou výjimku; časový limit
// požadavků; systémové „zpět" vede na rozumného rodiče.
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/friendly_error.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/net/timeout_client.dart';
import 'package:motogo_app/core/widgets/mg_back.dart';
import 'package:motogo_app/core/widgets/state_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

void main() {
  group('FriendlyError.kindOf', () {
    test('network failures → offline', () {
      expect(FriendlyError.kindOf(const SocketException('Failed host lookup')), FriendlyKind.offline);
      expect(FriendlyError.kindOf(http.ClientException('Connection closed')), FriendlyKind.offline);
      expect(FriendlyError.kindOf(AuthRetryableFetchException(message: 'x')), FriendlyKind.offline);
      expect(FriendlyError.kindOf(const FunctionsFetchException(details: SocketException('x'))),
          FriendlyKind.offline);
      expect(FriendlyError.kindOf(Exception('net::ERR_INTERNET_DISCONNECTED')), FriendlyKind.offline);
    });
    test('timeouts', () {
      expect(FriendlyError.kindOf(TimeoutException('t')), FriendlyKind.timeout);
      expect(FriendlyError.kindOf(FunctionsFetchException(details: TimeoutException('t'))),
          FriendlyKind.timeout);
      expect(FriendlyError.kindOf(const PostgrestException(message: 'canceling', code: '57014')),
          FriendlyKind.timeout);
    });
    test('server / auth / not found / rate limit / too large', () {
      expect(FriendlyError.kindOf(const FunctionException(status: 503)), FriendlyKind.server);
      expect(FriendlyError.kindOf(AuthRetryableFetchException(message: 'x', statusCode: '502')),
          FriendlyKind.server);
      expect(FriendlyError.kindOf(const FunctionException(status: 401)), FriendlyKind.auth);
      expect(FriendlyError.kindOf(const PostgrestException(message: 'JWT expired', code: 'PGRST301')),
          FriendlyKind.auth);
      expect(FriendlyError.kindOf(const PostgrestException(message: 'no rows', code: 'PGRST116')),
          FriendlyKind.notFound);
      expect(FriendlyError.kindOf(const PostgrestException(message: 'invalid input syntax for type uuid', code: '22P02')),
          FriendlyKind.notFound);
      expect(FriendlyError.kindOf(const FunctionException(status: 429)), FriendlyKind.rateLimit);
      expect(FriendlyError.kindOf(const FunctionException(status: 413)), FriendlyKind.tooLarge);
      expect(FriendlyError.kindOf(const StorageException('Payload too large', statusCode: '413')),
          FriendlyKind.tooLarge);
    });
    test('device permissions and location service', () {
      final cam = FriendlyError.of(PlatformException(code: 'camera_access_denied'));
      expect(cam.kind, FriendlyKind.permission);
      expect(cam.perm, DevicePerm.camera);
      expect(FriendlyError.of(Exception('CameraException(CameraAccessDenied, denied)')).perm,
          DevicePerm.camera);
      expect(FriendlyError.kindOf(Exception('LocationServiceDisabledException')),
          FriendlyKind.locationOff);
      expect(FriendlyError.of(Exception('x'), perm: DevicePerm.photos).perm, isNull);
    });
    test('unknown stays unknown', () {
      expect(FriendlyError.kindOf(Exception('weird')), FriendlyKind.unknown);
      expect(FriendlyError.kindOf(null), FriendlyKind.unknown);
    });
  });

  group('texts', () {
    final errors = <Object?>[
      const SocketException('x'),
      TimeoutException('x'),
      const FunctionException(status: 500),
      const FunctionException(status: 401),
      const PostgrestException(message: 'x', code: 'PGRST116'),
      PlatformException(code: 'camera_access_denied'),
      Exception('LocationServiceDisabledException'),
      const FunctionException(status: 429),
      const FunctionException(status: 413),
      Exception('boom: secret stack'),
    ];
    test('every kind has title/body/reason/hint in all 8 languages (no raw key, no raw error)', () {
      for (final lang in _langs) {
        final tr = AppTranslations.of(lang);
        for (final e in errors) {
          final fe = FriendlyError.of(e);
          for (final s in [fe.title(tr), fe.body(tr), fe.reason(tr), fe.hint(tr)]) {
            expect(s.startsWith('eo'), isFalse, reason: '$lang ${fe.kind}: missing key → "$s"');
            expect(s.contains('secret stack'), isFalse);
            expect(s.trim(), isNotEmpty);
          }
          final msg = fe.compose(tr, 'X');
          expect(msg.startsWith('X – '), isTrue);
        }
      }
    });
    test('all ext_37 keys exist in every language with identical placeholders', () {
      final cs = translations['cs']!;
      final keys = cs.keys.where((k) => k.startsWith('eo')).toList();
      expect(keys.length, greaterThan(150));
      final ph = RegExp(r'\{[a-z]+\}');
      for (final lang in _langs) {
        final m = translations[lang]!;
        for (final k in keys) {
          expect(m.containsKey(k), isTrue, reason: '$lang missing $k');
          final a = ph.allMatches(cs[k]!).map((x) => x.group(0)).toSet();
          final b = ph.allMatches(m[k]!).map((x) => x.group(0)).toSet();
          expect(b, a, reason: '$lang $k placeholders');
        }
      }
    });
    test('Czech error texts use tykání (no „Zkuste/Zkontrolujte/Povolte")', () {
      final cs = translations['cs']!;
      final formal = RegExp(r'\b(Zkuste|zkuste|Zkontrolujte|Povolte|Přihlaste|kontaktujte|Napište)\b');
      for (final k in [
        ...cs.keys.where((k) => k.startsWith('eo')),
        'offlineDesc', 'errUnknown', 'tryAgainPlease', 'notLoggedIn', 'sessionExpired',
        'errNetwork', 'errTimeout', 'errCameraPermission', 'scanSaveFailed', 'aiCommError',
        'writeFirstMessage', 'docNotAvailableYet', 'legalLoadFailed', 'doorCodesUnavailable',
      ]) {
        expect(formal.hasMatch(cs[k]!), isFalse, reason: '$k: ${cs[k]}');
      }
    });
  });

  group('TimeoutClient', () {
    test('limits per path', () {
      Duration l(String p) => TimeoutClient.limitFor(Uri.parse('https://x.supabase.co$p'));
      expect(l('/rest/v1/bookings'), const Duration(seconds: 20));
      expect(l('/rest/v1/rpc/get_x'), const Duration(seconds: 30));
      expect(l('/functions/v1/ai-moto-agent'), const Duration(seconds: 90));
      expect(l('/functions/v1/scan-document'), const Duration(seconds: 60));
      expect(l('/functions/v1/send-booking-email'), const Duration(seconds: 30));
      expect(l('/storage/v1/object/media/a.jpg'), const Duration(seconds: 120));
    });
    test('a stalled request ends with TimeoutException instead of hanging', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      final c = TimeoutClient(never, limits: (_) => const Duration(milliseconds: 50));
      await expectLater(c.get(Uri.parse('https://x/rest/v1/a')), throwsA(isA<TimeoutException>()));
    });
    test('normal responses pass through', () async {
      final ok = MockClient((_) async => http.Response('{"a":1}', 200));
      final c = TimeoutClient(ok, limits: (_) => const Duration(seconds: 1));
      final r = await c.get(Uri.parse('https://x/rest/v1/a'));
      expect(r.statusCode, 200);
      expect(r.body, '{"a":1}');
    });
  });

  group('mgBackParent', () {
    test('every screen has a sensible parent; Home and login exit', () {
      expect(mgBackParent('/'), isNull);
      expect(mgBackParent('/login'), isNull);
      expect(mgBackParent('/search'), '/');
      expect(mgBackParent('/reservations'), '/');
      expect(mgBackParent('/routes'), '/');
      expect(mgBackParent('/profile'), '/');
      expect(mgBackParent('/reservations/abc'), '/reservations');
      expect(mgBackParent('/reservations/abc/edit'), '/reservations/abc');
      expect(mgBackParent('/messages'), '/profile');
      expect(mgBackParent('/messages/t1'), '/messages');
      expect(mgBackParent('/sos'), '/');
      expect(mgBackParent('/sos/accident'), '/sos');
      expect(mgBackParent('/sos/done'), '/');
      expect(mgBackParent('/shop/p1'), '/shop');
      expect(mgBackParent('/checkout'), '/cart');
      expect(mgBackParent('/docs/scan'), '/docs');
      expect(mgBackParent('/route-nav/r1'), '/routes/r1');
      expect(mgBackParent('/routes/r1'), '/routes-list');
      expect(mgBackParent('/ride/x'), '/my-experiences');
      expect(mgBackParent('/register'), '/login');
      expect(mgBackParent('/reset-password'), '/login');
      expect(mgBackParent('/totally-unknown'), '/');
    });
  });

  group('MgErrorView', () {
    testWidgets('shows what/why, retry and back; never the raw error', (tester) async {
      var retried = 0, backed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MgErrorView(
            error: const SocketException('Failed host lookup: secret.host'),
            what: 'Zprávy se nepodařilo načíst',
            onRetry: () => retried++,
            onBack: () => backed++,
          ),
        ),
      ));
      // MaterialApp bez lokalizací = angličtina.
      final tr = AppTranslations.of('en');
      expect(find.text('Zprávy se nepodařilo načíst'), findsOneWidget);
      expect(find.textContaining(tr.tr('eoOfflineBody')), findsOneWidget);
      expect(find.textContaining('secret.host'), findsNothing);
      await tester.tap(find.text(tr.tr('eoRetry')));
      await tester.tap(find.text(tr.tr('eoBack')));
      expect(retried, 1);
      expect(backed, 1);
    });
  });
}
