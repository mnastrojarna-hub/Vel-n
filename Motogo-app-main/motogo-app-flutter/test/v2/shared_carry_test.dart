// „Nic nevyplňovat dvakrát“ mimo formulář rezervace (majitel 2026-10-22):
// Domů v2 nemaže termín ani rozpracovanou rezervaci (starý vzhled beze
// změny), e-mail se nese mezi přihlášením a registrací, SOS náhrada nabídne
// adresu „Kde právě jsi“ (8 jazyků × 2 velikosti).
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
import 'package:motogo_app/core/i18n/translations.dart' show translations;
import 'package:motogo_app/core/router.dart' show Routes;
import 'package:motogo_app/core/shell_tab_action.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/widgets/address_autocomplete_field.dart' show AddressSuggestion;
import 'package:motogo_app/features/auth/login_screen.dart';
import 'package:motogo_app/features/auth/register_screen.dart';
import 'package:motogo_app/features/auth/widgets/login_buttons.dart' show LoginRegisterButton;
import 'package:motogo_app/features/auth/widgets/login_form_fields.dart' show LoginEmailField;
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/v2/booking_carry_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/payment/payment_provider.dart' show lastConfirmedBookingProvider;
import 'package:motogo_app/features/sos/sos_here_address.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/v2_harness.dart';

final _s = DateTime(2027, 5, 7), _e = DateTime(2027, 5, 9);

Widget _tabs(String path) => Scaffold(
      body: Consumer(builder: (c, ref, _) {
        Future<void> tap(String route) =>
            onShellTabTap(c, ref, route: route, isActive: false, isHome: route == '/', location: path);
        return Column(children: [
          Text('PAGE $path'),
          TextButton(onPressed: () => tap('/'), child: const Text('TAB-HOME')),
          TextButton(onPressed: () => tap('/search'), child: const Text('TAB-BIKES')),
        ]);
      }),
    );

Widget _app(GoRouter router, {bool v2 = true}) => ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('cs'),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: v2TestTheme(),
        builder: (c, child) => MgV2Scope(
          enabled: v2,
          child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling), child: child!),
        ),
      ),
    );

Future<ProviderContainer> _pumpTabs(WidgetTester tester, {required bool v2}) async {
  final router = GoRouter(initialLocation: '/search', routes: [
    for (final p in ['/', '/search']) GoRoute(path: p, builder: (_, __) => _tabs(p)),
  ]);
  await tester.pumpWidget(_app(router, v2: v2));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('PAGE /search')));
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void _seed(ProviderContainer c) {
  c.read(catalogFilterProvider.notifier).state = CatalogFilter(branch: 'brno', startDate: _s, endDate: _e);
  c.read(bookingDraftProvider.notifier).state = BookingDraft(motoId: 'm1', startDate: _s, endDate: _e, notes: 'Přijedu autem');
  c.read(bookingEntryFilterProvider.notifier).state = (_s, _e);
}

Future<GoRouter> _pumpAuth(WidgetTester tester, {String? saved}) async {
  SharedPreferences.setMockInitialValues({if (saved != null) 'mg_saved_email': saved});
  tester.view.physicalSize = const Size(412, 915) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: Routes.login, routes: [
    GoRoute(path: Routes.login, builder: (_, s) => LoginScreen(initialEmail: s.uri.queryParameters['email'])),
    GoRoute(path: Routes.register, builder: (_, s) => RegisterScreen(initialEmail: s.uri.queryParameters['email'])),
  ]);
  await tester.pumpWidget(_app(router, v2: false));
  await tester.pumpAndSettle();
  return router;
}

String _field(WidgetTester tester, Finder of) =>
    tester.widget<EditableText>(find.descendant(of: of, matching: find.byType(EditableText)).first).controller.text;

void main() {
  setUpAll(loadMontserrat);

  group('Domů a rozpracovaná rezervace', () {
    testWidgets('v2: Domů nemaže termín, filtr ani rozpracovaný formulář', (tester) async {
      final c = await _pumpTabs(tester, v2: true);
      _seed(c);
      await _tap(tester, 'TAB-HOME');
      expect(find.text('PAGE /'), findsOneWidget);
      final f = c.read(catalogFilterProvider);
      expect((f.startDate, f.endDate, f.branch), (_s, _e, 'brno'));
      expect(c.read(bookingDraftProvider).motoId, 'm1');
      expect(c.read(bookingDraftProvider).notes, 'Přijedu autem');
    });

    testWidgets('starý vzhled: Domů resetuje jako dřív', (tester) async {
      final c = await _pumpTabs(tester, v2: false);
      _seed(c);
      await _tap(tester, 'TAB-HOME');
      expect(c.read(catalogFilterProvider).startDate, isNull);
      expect(c.read(catalogFilterProvider).branch, isNull);
      expect(c.read(bookingDraftProvider).motoId, isNull);
    });

    testWidgets('v2 po zaplacení: zahodí draft i termín hotové rezervace, nový termín pak drží', (tester) async {
      final c = await _pumpTabs(tester, v2: true);
      _seed(c);
      c.read(lastConfirmedBookingProvider.notifier).state = 'b1';
      await _tap(tester, 'TAB-HOME');
      expect(c.read(bookingDraftProvider).motoId, isNull);
      expect(c.read(catalogFilterProvider).startDate, isNull);
      expect(c.read(bookingDraftSeedMarkProvider), 'b1');
      // Další termín už Domů nemaže.
      final s2 = DateTime(2027, 6, 1), e2 = DateTime(2027, 6, 3);
      await _tap(tester, 'TAB-BIKES');
      c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: s2, endDate: e2);
      await _tap(tester, 'TAB-HOME');
      expect(c.read(catalogFilterProvider).startDate, s2);
    });

    testWidgets('v2 po zaplacení: termín zvolený až po vstupu do formuláře zůstává', (tester) async {
      final c = await _pumpTabs(tester, v2: true);
      _seed(c);
      final s2 = DateTime(2027, 7, 1), e2 = DateTime(2027, 7, 4);
      c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: s2, endDate: e2);
      c.read(lastConfirmedBookingProvider.notifier).state = 'b1';
      await _tap(tester, 'TAB-HOME');
      expect(c.read(bookingDraftProvider).motoId, isNull);
      expect((c.read(catalogFilterProvider).startDate, c.read(catalogFilterProvider).endDate), (s2, e2));
    });
  });

  group('E-mail mezi přihlášením a registrací', () {
    testWidgets('napsaný e-mail jde do registrace', (tester) async {
      await _pumpAuth(tester, saved: 'stary@ucet.cz');
      expect(_field(tester, find.byType(LoginEmailField)), 'stary@ucet.cz');
      await tester.enterText(find.descendant(of: find.byType(LoginEmailField), matching: find.byType(EditableText)), 'novy@zakaznik.cz');
      await tester.ensureVisible(find.byType(LoginRegisterButton));
      await tester.tap(find.byType(LoginRegisterButton));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'novy@zakaznik.cz'), findsOneWidget);
    });

    testWidgets('zapamatovaný e-mail existujícího účtu se do registrace nenese', (tester) async {
      await _pumpAuth(tester, saved: 'stary@ucet.cz');
      await tester.ensureVisible(find.byType(LoginRegisterButton));
      await tester.tap(find.byType(LoginRegisterButton));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'stary@ucet.cz'), findsNothing);
    });

    testWidgets('registrace → „účet existuje, Přihlásit“ (go s ?email=) vyplní už otevřené přihlášení', (tester) async {
      final router = await _pumpAuth(tester, saved: 'stary@ucet.cz');
      await tester.ensureVisible(find.byType(LoginRegisterButton));
      await tester.tap(find.byType(LoginRegisterButton));
      await tester.pumpAndSettle();
      router.go(Uri(path: Routes.login, queryParameters: {'email': 'zabrany@ucet.cz'}).toString());
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsNothing);
      expect(_field(tester, find.byType(LoginEmailField)), 'zabrany@ucet.cz');
    });

    testWidgets('přihlášení s e-mailem z registrace (?email=) má přednost před zapamatovaným', (tester) async {
      SharedPreferences.setMockInitialValues({'mg_saved_email': 'stary@ucet.cz'});
      await pumpV2(tester, const LoginScreen(initialEmail: 'a+b@zakaznik.cz'), v2: false, scaffold: false);
      await tester.pumpAndSettle();
      expect(_field(tester, find.byType(LoginEmailField)), 'a+b@zakaznik.cz');
      final uri = Uri.parse(Uri(path: Routes.login, queryParameters: {'email': 'a+b@zakaznik.cz'}).toString());
      expect(uri.queryParameters['email'], 'a+b@zakaznik.cz');
    });
  });

  group('SOS náhrada — Kde právě jsi', () {
    const here = AddressSuggestion(street: 'Masarykova 12', city: 'Brno', zip: '60200', lat: 49.19, lng: 16.6);

    testWidgets('poloha zjištěná předem → adresa jedním klepnutím', (tester) async {
      AddressSuggestion? picked;
      await pumpV2(tester, SosHereAddress(onPick: (s) => picked = s, locate: () async => here), v2: false);
      await tester.pumpAndSettle();
      expect(find.text('Masarykova 12, Brno'), findsOneWidget);
      expect(picked, isNull); // nic se nevyplní samo
      await tester.tap(find.byType(SosHereAddress));
      await tester.pumpAndSettle();
      expect(picked?.street, 'Masarykova 12');
      expect(find.textContaining('Adresu můžeš upravit'), findsOneWidget);
    });

    testWidgets('klepnutí během zjišťování adresu použije, jakmile je', (tester) async {
      final done = Completer<AddressSuggestion?>();
      AddressSuggestion? picked;
      await pumpV2(tester, SosHereAddress(onPick: (s) => picked = s, locate: () => done.future), v2: false);
      await tester.pump();
      expect(find.text('Zjišťuji polohu...'), findsOneWidget);
      await tester.tap(find.byType(SosHereAddress));
      done.complete(here);
      await tester.pumpAndSettle();
      expect(picked?.city, 'Brno');
    });

    testWidgets('bez polohy: vysvětlení a adresa zůstává k ručnímu zadání', (tester) async {
      var calls = 0;
      AddressSuggestion? picked;
      await pumpV2(tester, SosHereAddress(onPick: (s) => picked = s, locate: () async {
        calls++;
        return null;
      }), v2: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SosHereAddress));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 2);
      expect(picked, isNull);
      expect(find.textContaining('GPS signál'), findsOneWidget);
    });

    for (final lang in kV2Langs) {
      for (final size in kV2Sizes) {
        testWidgets('render $lang ${size.width.toInt()}', (tester) async {
          await pumpV2(tester, Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              SosHereAddress(onPick: (_) {}, locate: () async => null),
              const SizedBox(height: 8),
              SosHereAddress(onPick: (_) {}, locate: () async => here),
            ]),
          ), lang: lang, size: size, v2: false);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SosHereAddress).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final tr = translations[lang]!;
          expect(find.text(tr['sosHereTitle']!), findsNWidgets(2));
          expect(find.text(tr['sosHereTap']!), findsOneWidget);
          expect(find.text(tr['sosHereUsed']!), findsOneWidget);
        });
      }
    }

    test('adresa z Mapy.com, záložně Nominatim, jinak souřadnice', () async {
      final mapy = MockClient((r) async => http.Response(
          jsonEncode({
            'items': [
              {
                'name': 'Masarykova 12',
                'zip': '602 00',
                'regionalStructure': [
                  {'type': 'regional.address', 'name': 'Masarykova 12'},
                  {'type': 'regional.municipality', 'name': 'Brno'},
                ],
              },
            ],
          }),
          200));
      final a = await sosAddressAt(49.19, 16.6, client: mapy);
      expect((a.street, a.city, a.zip), ('Masarykova 12', 'Brno', '602 00'));

      final nomi = MockClient((r) async => r.url.host == 'api.mapy.cz'
          ? http.Response('{"items":[]}', 200)
          // UTF-8 bez charset v hlavičce (diakritika se nesmí rozbít).
          : http.Response.bytes(utf8.encode(jsonEncode({'address': {'road': 'Kotlářská', 'house_number': '5', 'town': 'Brno', 'postcode': '60200'}})), 200));
      final b = await sosAddressAt(49.19, 16.6, client: nomi);
      expect((b.street, b.city), ('Kotlářská 5', 'Brno'));

      final off = MockClient((r) async => throw const SocketExceptionLike());
      final c = await sosAddressAt(49.191234, 16.601234, client: off);
      expect(c.street, 'GPS 49.19123, 16.60123');
      expect(c.lat, 49.191234);
    });
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
