// 5.0.2: Místa — výpadek komunitních míst (živá DB neměla get_user_pois)
// už neukazuje kartu „Místa se nepodařilo načíst“, když se katalog načetl;
// chyba katalogu bez dat ji ukáže dál.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/all_pois_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRoutesStrings();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  final err = find.textContaining('Místa se nepodařilo načíst');

  testWidgets('komunitní místa selžou, katalog ano → bez chyby', (tester) async {
    await pumpV2(tester, const AllPoisScreen(asTab: true),
        lang: 'cs', size: const Size(360, 780), overrides: routesOverrides(userFail: true));
    await tester.pump(const Duration(seconds: 1));
    expect(err, findsNothing);
    expect(tester.takeException(), isNull);
    await rtEnd(tester);
  });

  testWidgets('katalog selže bez dat → chyba zůstává', (tester) async {
    await pumpV2(tester, const AllPoisScreen(asTab: true),
        lang: 'cs', size: const Size(360, 780), overrides: routesOverrides(catalogFail: true, routes: const []));
    await tester.pump(const Duration(seconds: 1));
    expect(err, findsOneWidget);
    await rtEnd(tester);
  });
}
