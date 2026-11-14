// D4 (owner 2026-11-14, "i ten skener ano"; G-556): two immediate
// "Přeskočit" taps on the LAST scanner step finished the scan twice — the
// documents were verified twice (the same defect is in the released 4.1.3).
// Both looks share `DocumentScannerScreen._finalize`: now exactly one
// `verify_customer_docs` call, counted on the fake Supabase backend.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/features/documents/document_scanner_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../journey/journey_backend.dart';
import '../support/v2_harness.dart';

const _camera = MethodChannel('plugins.flutter.io/camera');

Future<void> _pumpScanner(WidgetTester t, {required bool v2}) async {
  t.view.physicalSize = const Size(360, 780) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: Routes.docScan, routes: [
    GoRoute(path: Routes.home, builder: (_, __) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: Routes.docs, builder: (_, __) => const Scaffold(body: Text('DOCS'))),
    GoRoute(path: Routes.docScan, builder: (_, __) => const DocumentScannerScreen(scanMode: 'dl_only')),
  ]);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('cs'),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2 ? v2TestTheme() : legacyTestTheme(),
      builder: (context, c) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: c!,
        ),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

int _verifyCalls() => journeyRequests.where((r) => r.endsWith('/rpc/verify_customer_docs')).length;

void main() {
  setUpAll(() async {
    await loadMontserrat();
    SharedPreferences.setMockInitialValues({});
    await initJourneyBackend();
    await journeySetLoggedIn(true);
  });

  setUp(() {
    journeyRequests.clear();
    // The camera never answers: no error screen, the step controls (with
    // "Přeskočit") stay on screen as on a phone while the camera starts.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_camera, (call) => Completer<Object?>().future);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_camera, null);
  });

  for (final v2 in [true, false]) {
    final look = v2 ? 'new look' : 'old look';
    final skip = v2 ? 'Přeskočit' : 'Přeskočit →';

    testWidgets('$look: double skip on the last step verifies the documents once', (t) async {
      await _pumpScanner(t, v2: v2);
      // dl_only = 2 steps (ŘP front, back): the first skip goes to the last.
      await t.tap(find.text(skip));
      await t.pump();
      expect(find.text(skip), findsOneWidget);
      // Two immediate taps on the last step (no frame in between).
      await t.tap(find.text(skip));
      await t.tap(find.text(skip), warnIfMissed: false);
      await t.pump();
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      expect(_verifyCalls(), 1);
      // The single finalize still finishes the scan: back to Moje doklady.
      expect(find.text('DOCS'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('$look: a single skip on the last step still finishes the scan', (t) async {
      await _pumpScanner(t, v2: v2);
      await t.tap(find.text(skip));
      await t.pump();
      await t.tap(find.text(skip));
      await t.pump();
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      expect(_verifyCalls(), 1);
      expect(find.text('DOCS'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
