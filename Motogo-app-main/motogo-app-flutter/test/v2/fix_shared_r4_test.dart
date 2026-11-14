// fix:shared r4 — SOS replacement (journey 7) is no dead end: the list
// offers only bikes free for the rest of the rental (the broken one, trailers
// and bikes in maintenance left out), and when the server still refuses the
// bike ("není do konce pronájmu volná", P0001) the customer gets the reason
// and goes back to the list instead of a generic Retry that fails again.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/supabase_client.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/sos/sos_provider.dart';
import 'package:motogo_app/features/sos/sos_replacement_motos.dart';
import 'package:motogo_app/features/sos/sos_replacement_screen.dart';
import 'package:motogo_app/features/sos/v2/sos_actions_v2.dart' show SosNeonButtonV2;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/v2_harness.dart';

const _taken = 'Vybraná motorka není do konce pronájmu volná — vyberte prosím jinou.';

const _motos = [
  Motorcycle(id: 'm1', model: 'BMW R 1250 GS Adventure', category: 'cestovni'),
  Motorcycle(id: 'm2', model: 'Kawasaki Z900', category: 'naked'),
];

SosIncident _inc() => SosIncident(
    id: 'abcdef12-3456-7890-abcd-ef1234567890',
    type: 'breakdown_major',
    status: 'reported',
    motoId: 'm9',
    bookingEndDate: DateTime(2026, 10, 5),
    createdAt: DateTime(2026, 10, 1, 9));

/// Supabase whose `sos_swap_bookings` answers like the live RPC does for a
/// taken bike; everything else answers an empty list.
Future<void> _supabaseRefusingSwap() async {
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: MotoGoSupabase.url,
    publishableKey: 'test-anon',
    httpClient: MockClient((req) async {
      final json = {'content-type': 'application/json; charset=utf-8'};
      if (req.url.path.endsWith('/rpc/sos_swap_bookings')) {
        return http.Response(
            jsonEncode({'code': 'P0001', 'message': _taken, 'details': null, 'hint': null}), 400,
            headers: json, request: req);
      }
      return http.Response('[]', 200, headers: json, request: req);
    }),
    authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false),
    debug: false,
  );
}

void main() {
  setUpAll(loadMontserrat);

  group('replacement candidates', () {
    test('range: today → booking end, never in the past', () {
      final now = DateTime(2026, 10, 3, 14, 30);
      expect(sosReplacementRange(now, DateTime(2026, 10, 5, 18)), (DateTime(2026, 10, 3), DateTime(2026, 10, 5)));
      expect(sosReplacementRange(now, DateTime(2026, 10, 1)), (DateTime(2026, 10, 3), DateTime(2026, 10, 3)));
      expect(sosReplacementRange(now, null), (DateTime(2026, 10, 3), DateTime(2026, 10, 3)));
    });

    test('the broken bike, trailers, maintenance and closed branches are left out', () {
      const all = [
        Motorcycle(id: 'cur', model: 'Current'),
        Motorcycle(id: 'ok', model: 'Free one'),
        Motorcycle(id: 'tr', model: 'Vozík', isTrailer: true),
        Motorcycle(id: 'mt', model: 'In service', status: 'maintenance'),
        Motorcycle(id: 'cl', model: 'Closed branch', branchIsOpen: false),
        Motorcycle(id: 'ok2', model: 'Active', status: 'active', branchIsOpen: true),
      ];
      expect(sosReplacementCandidates(all, 'cur').map((m) => m.id), ['ok', 'ok2']);
      expect(sosReplacementCandidates(all, null).map((m) => m.id), ['cur', 'ok', 'ok2']);
    });

    test('isSosMotoTakenError: only the availability RAISE of sos_swap_bookings', () {
      expect(isSosMotoTakenError(const PostgrestException(message: _taken, code: 'P0001')), isTrue);
      expect(
          isSosMotoTakenError(const PostgrestException(
              message: 'Incident je uzavřen — náhradní motorku vyřídí operátor MotoGo24.', code: 'P0001')),
          isFalse);
      expect(isSosMotoTakenError(const PostgrestException(message: _taken, code: '42501')), isFalse);
      expect(isSosMotoTakenError(Exception(_taken)), isFalse);
      expect(isSosMotoTakenError(null), isFalse);
    });
  });

  for (final lang in ['cs', 'uk']) {
    testWidgets('taken bike ($lang): reason + back to the list, no generic Retry', (tester) async {
      await _supabaseRefusingSwap();
      // The incident provider is alive in the app (SOS screens / Home banner
      // watch it) — `_confirm` reads it; keep it alive here the same way.
      await pumpV2(
          tester,
          Consumer(builder: (c, ref, _) {
            ref.watch(activeSosProvider);
            return const SosReplacementScreen();
          }),
          lang: lang,
          size: const Size(360, 780),
          dpr: 1,
          reducedMotion: true,
          scaffold: false,
          overrides: [
            sosReplacementMotosProvider.overrideWith((ref) async => _motos),
            activeSosProvider.overrideWith((ref) => Stream.value(_inc())),
          ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Kawasaki Z900'), findsOneWidget);
      await tester.tap(find.text('Kawasaki Z900'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Lidická 5, Brno');
      await tester.pump(const Duration(seconds: 1)); // address debounce
      // v2 look (ASM-25): the confirm sits in the night SOS dock.
      await tester.tap(find.byType(SosNeonButtonV2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      final title = lang == 'cs' ? 'Tahle motorka už není volná' : 'Цей мотоцикл уже не вільний';
      final pick = lang == 'cs' ? 'Vybrat jinou' : 'Обрати інший';
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining(lang == 'cs' ? 'Vyber prosím jinou' : 'Обери, будь ласка, інший'), findsOneWidget);
      expect(find.text('🆘 112'), findsNothing); // not the generic SOS failure dialog
      await tester.tap(find.text(pick));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(title), findsNothing);
      // Back on the list, nothing selected any more.
      final opts = tester.widgetList(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_SosBikeRowV2'));
      expect(opts.length, 2);
      expect(opts.every((w) => (w as dynamic).selected == false), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
