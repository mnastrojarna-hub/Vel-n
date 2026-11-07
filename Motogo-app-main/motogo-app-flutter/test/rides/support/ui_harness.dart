// Harness pro widget testy starého vzhledu záznamu jízd (oba stromy appky —
// nic z test/v2): jazyk, šířka telefonu, zvětšení písma 1.3, reduced
// motion, skutečný Montserrat (když je v pub cache), falešný záznamník.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';

const kRpLangs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
const kRpWidths = [320.0, 412.0];
const kRpScales = [1.0, 1.3];

bool _fontsTried = false;

/// Montserrat z `flutter_gallery_assets` v pub cache — šířky textu jako
/// v appce (bez něj testovací písmo kreslí čtverce 1 em).
Future<void> loadRidesFont() async {
  if (_fontsTried) return;
  _fontsTried = true;
  final home = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME'] ?? ''}/.pub-cache';
  final dir = Directory('$home/hosted/pub.dev/flutter_gallery_assets-1.0.2/lib/fonts/google_fonts');
  if (!dir.existsSync()) return;
  final loader = FontLoader('Montserrat');
  var n = 0;
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final f = File('${dir.path}/Montserrat-$w.ttf');
    if (!f.existsSync()) continue;
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
    n++;
  }
  if (n > 0) await loader.load();
}

/// Záznamník s pevným stavem; akce jen zapíše a stav posune jako appka.
class FakeRec extends RideRecorderNotifier {
  FakeRec(super.ref, this.initial, {this.resumeResult = RideStartResult.ok}) {
    state = initial;
    // `_restore()` předka doběhne asynchronně — stav se vrátí na pevný.
    Future<void>.delayed(const Duration(milliseconds: 30), () {
      if (mounted && calls.isEmpty) state = initial;
    });
  }

  final RideRecorderState initial;
  final RideStartResult resumeResult;
  final List<String> calls = [];

  @override
  Future<void> pause() async {
    calls.add('pause');
    state = state.copyWith(phase: RidePhase.manualPaused, pauseReason: RidePauseReason.manual);
  }

  @override
  Future<RideStartResult> resume() async {
    calls.add('resume');
    if (resumeResult == RideStartResult.ok) {
      state = state.copyWith(phase: RidePhase.autoPaused, pauseReason: RidePauseReason.start);
    }
    return resumeResult;
  }

  @override
  Future<bool?> stop() async {
    calls.add('stop');
    state = state.copyWith(recording: false, clearRide: true);
    return true;
  }

  @override
  Future<void> discardCurrent() async => calls.add('discard');

  @override
  Future<void> setEnabled(bool value) async => calls.add('setEnabled:$value');
}

/// Přepisy providerů: záznamník + seznam jízd (+ jízdy výpůjčky).
List<Override> ridesUiOverrides({
  RideRecorderState rec = const RideRecorderState(),
  List<UserRide> rides = const [],
  Map<String, List<UserRide>> booking = const {},
  RideStartResult resumeResult = RideStartResult.ok,
}) =>
    [
      rideRecorderProvider.overrideWith((ref) => FakeRec(ref, rec, resumeResult: resumeResult)),
      myRidesProvider.overrideWith((ref) async => rides),
      bookingRidesProvider.overrideWith((ref, id) async => booking[id] ?? const []),
    ];

/// Vykreslí [child] jako appka: jazyk, šířka, zvětšení písma, reduced motion.
Future<void> pumpRides(
  WidgetTester tester,
  Widget child, {
  String lang = 'cs',
  double width = 412,
  double height = 900,
  double scale = 1.0,
  bool reducedMotion = false,
  List<Override> overrides = const [],
  bool scroll = true,
  GlobalKey? boundaryKey,
}) async {
  // Čistý strom: nový ProviderScope (přepisy providerů se jinak nemění)
  // a žádný sheet / dialog z minulého vykreslení.
  await tester.pumpWidget(const SizedBox());
  tester.view.physicalSize = Size(width, height) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(fontFamily: 'Montserrat', useMaterial3: true),
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: c!,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFFDFF0EC),
        body: scroll
            ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)
            : child,
      ),
    ),
    ),
  ));
}

/// Pár snímků bez výjimky / přetečení.
Future<void> expectCleanRides(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
  await tester.pump(const Duration(milliseconds: 600));
  expect(tester.takeException(), isNull);
}
