// Level-up oslava — testovací rig: skutečný `LoyaltyLevelUpWatcher` +
// `loyaltyStatusProvider` proti falešnému Supabase (bez sítě), router s
// kořenovým navigátorem appky a stejná skladba jako `MaterialApp.builder`
// v main.dart (Listener → Stack[navigátor, hlídač]).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/supabase_client.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_levelup_overlay.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/main.dart' show rootNavigatorKey;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const uidA = '0f0f0f0f-1111-4222-8333-444444444444';
const uidB = '0f0f0f0f-1111-4222-8333-555555555555';

String markerKey(String uid) => 'mg_loyalty_celebrated_$uid';
String legacyKey(String uid) => 'mg_loyalty_last_level_$uid';

/// Stav falešného serveru (jeden účet; `loyalty_advance_celebrated` = GREATEST).
class FakeLoyalty {
  int level = 1;
  int celebrated = 0;

  /// `loyalty_get_celebrated` selže (výpadek) / RPC v DB vůbec nejsou.
  bool failGet = false;
  bool failAdvance = false;
  bool failStatus = false;
  bool rpcMissing = false;

  /// Odpověď počká na dokončení (přepnutí účtu „během awaitů").
  Completer<void>? getGate;
  Completer<void>? motosGate;

  /// Úspěšné zápisy `loyalty_advance_celebrated` (p_level) v pořadí.
  final advances = <int>[];
  int statusCalls = 0;
  int getCalls = 0;
}

FakeLoyalty fake = FakeLoyalty();
http.Request? _req;

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    request: _req, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _missing(String fn) => _json(
    {'code': 'PGRST202', 'message': 'Could not find the function public.$fn in the schema cache'}, 404);

Future<http.Response> _handle(http.Request r) async {
  _req = r;
  final p = r.url.path;
  if (p.endsWith('/rpc/get_loyalty_status')) {
    fake.statusCalls++;
    if (fake.failStatus) return _json({'message': 'offline', 'code': 'XX000'}, 503);
    return _json({
      'level': fake.level,
      'percent': fake.level,
      'rank_name': 'Rank ${fake.level}',
      'color_hex': '#22C55E',
      'qualifying_count': fake.level * 2 - 1,
      'max_level': 20,
    });
  }
  if (p.endsWith('/rpc/loyalty_get_celebrated')) {
    fake.getCalls++;
    final gate = fake.getGate;
    if (gate != null) {
      await gate.future;
      _req = r;
    }
    if (fake.rpcMissing) return _missing('loyalty_get_celebrated');
    if (fake.failGet) return _json({'message': 'boom', 'code': 'XX000'}, 500);
    return _json(fake.celebrated);
  }
  if (p.endsWith('/rpc/loyalty_advance_celebrated')) {
    if (fake.rpcMissing) return _missing('loyalty_advance_celebrated');
    if (fake.failAdvance) return _json({'message': 'boom', 'code': 'XX000'}, 500);
    final lvl = (jsonDecode(r.body) as Map)['p_level'] as int;
    fake.advances.add(lvl);
    if (lvl > fake.celebrated) fake.celebrated = lvl;
    return _json(fake.celebrated);
  }
  if (p.endsWith('/rpc/get_loyalty_celebration_motos')) {
    final gate = fake.motosGate;
    if (gate != null) {
      await gate.future;
      _req = r;
    }
    return _json({'is_personalized': false, 'motos': []});
  }
  return _json(const []);
}

bool _init = false;
String _b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// Přihlásí falešného zákazníka bez volání serveru (lokálně obnovená session).
Future<void> loginAs(WidgetTester tester, String uid) => tester.runAsync(() async {
      final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
      final jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
          '${_b64({'sub': uid, 'exp': exp, 'role': 'authenticated', 'aud': 'authenticated'})}.c2ln';
      await Supabase.instance.client.auth.recoverSession(jsonEncode({
        'access_token': jwt,
        'expires_in': 315360000,
        'expires_at': exp,
        'refresh_token': 'r',
        'token_type': 'bearer',
        'user': {
          'id': uid,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'z@example.cz',
          'created_at': '2025-01-01T10:00:00Z',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
        },
      }));
    });

class _Page extends ConsumerWidget {
  final String label;
  const _Page(this.label);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Jako logo / hlavičky appky: rank sleduje skoro každá obrazovka.
    final lvl = ref.watch(loyaltyStatusProvider).valueOrNull?.level;
    return Scaffold(body: Center(child: Text('$label ${lvl ?? ''}')));
  }
}

late GoRouter router;
late ProviderContainer container;
late SharedPreferences prefs;

final celebration = find.byType(LevelUpCelebration);

/// Spustí appku se zákazníkem A. [overlay] / [payment] = blokace je aktivní
/// už při první kontrole (intro po studeném startu / platební obrazovka).
Future<void> boot(
  WidgetTester tester, {
  bool overlay = false,
  bool payment = false,
  Stream<List<Reservation>>? reservations,
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  prefs = await SharedPreferences.getInstance();
  if (!_init) {
    _init = true;
    await Supabase.initialize(
      url: MotoGoSupabase.url,
      publishableKey: 'test-anon',
      httpClient: MockClient(_handle),
      authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false),
      debug: false,
    );
  }
  if (MotoGoSupabase.currentUser?.id != uidA) await loginAs(tester, uidA);
  loyaltyPollPaused = false;
  resetLoyaltyPollClock();
  clearLoyaltyStatusCache();
  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (c, s, child) => child,
        routes: [
          GoRoute(path: '/', builder: (_, __) => const _Page('HOME')),
          GoRoute(path: '/tab', builder: (_, __) => const _Page('TAB')),
        ],
      ),
      GoRoute(path: '/out', builder: (_, __) => const _Page('OUT')),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      reservationsProvider.overrideWith((ref) => reservations ?? const Stream<List<Reservation>>.empty()),
      profileProvider.overrideWith((ref) async => <String, dynamic>{'id': uidA}),
      if (overlay) onboardingOverlayActiveProvider.overrideWith((ref) => true),
      if (payment) paymentScreenActiveProvider.overrideWith((ref) => true),
    ],
    child: Consumer(builder: (context, ref, _) {
      return MaterialApp.router(
        routerConfig: router,
        locale: const Locale('cs'),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => maybeRefreshLoyalty(ref),
          child: Stack(children: [child!, const LoyaltyLevelUpWatcher()]),
        ),
      );
    }),
  ));
  container = ProviderScope.containerOf(tester.element(find.byType(LoyaltyLevelUpWatcher)));
}

/// Nechá doběhnout RPC a pár snímků ([ms] falešného času po 50 ms).
Future<void> settle(WidgetTester t, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Běžný rytmus kontrol (dotyk / časovač / návrat) → nová kontrola ranku.
Future<void> recheck(WidgetTester t) async {
  container.invalidate(loyaltyStatusProvider);
  await settle(t);
}

/// „Pokračovat" ve chvíli, kdy už je tlačítko vidět.
Future<void> tapContinue(WidgetTester t) async {
  await t.tap(find.text('Pokračovat'));
  await settle(t);
}

/// Konec testu: zahodí strom (časovače hlídače) a uvolní globální pauzu.
Future<void> unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
  loyaltyPollPaused = false;
}
