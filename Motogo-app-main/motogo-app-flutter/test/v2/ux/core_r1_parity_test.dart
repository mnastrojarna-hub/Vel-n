// fix:r1:core — iOS edge back look (no veil, canvas behind, page state
// kept), T2 sheet ✕ on the disc row, segment swipe repaints only its layer,
// one live indicator on Domů while recording, record row never splits a
// word (320 dp, 8 languages).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/gestures/mg_edge_back.dart';
import 'package:motogo_app/core/v2/gestures/mg_swipe.dart';
import 'package:motogo_app/core/v2/motion/mg_anim_loops.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_sheet.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/core/v2/widgets/mg_sheet.dart';
import 'package:motogo_app/features/home/v2/funnel_carousel_v2.dart';
import 'package:motogo_app/features/home/v2/home_record_row_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart' show midWordBreak;
import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart';
import '../support/v2_harness.dart';

int _inits = 0;

class _Counted extends StatefulWidget {
  const _Counted();
  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    _inits++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.white, child: SizedBox.expand());
}

Future<Color> _pixel(WidgetTester tester, GlobalKey key, Offset at) async {
  final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final ui.Image img = await ro.toImage();
    return img.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final i = (at.dy.round() * ro.size.width.round() + at.dx.round()) * 4;
  final b = bytes!;
  return Color.fromARGB(b.getUint8(i + 3), b.getUint8(i), b.getUint8(i + 1), b.getUint8(i + 2));
}

void main() {
  setUpAll(() async {
    // Montserrat incl. ExtraBold / Black when MG_FONTS_DIR is set (the render
    // gate's fonts — the "Enregistreme|nt" split needed the real w800).
    await loadRenderFonts();
    registerHomeStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  testWidgets('MgEdgeBack iOS mid-drag: page centre unveiled, uncovered strip = canvas (never black), page state kept', (tester) async {
    _inits = 0;
    final key = GlobalKey();
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(backgroundColor: Colors.black, body: MgEdgeBack(onBack: () {}, child: const _Counted())),
      ),
    ));
    final before = await _pixel(tester, key, const Offset(180, 390));
    final g = await tester.startGesture(const Offset(5, 390));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Page shifted by 112 px: its centre now sits at x = 292.
    expect(await _pixel(tester, key, const Offset(292, 390)), before);
    expect(await _pixel(tester, key, const Offset(40, 390)), MgColors.canvas);
    await g.up();
    await tester.pumpAndSettle();
    expect(_inits, 1, reason: 'the page element survives the drag');
  });

  testWidgets('T2 sheet without a title: ✕ on the tone disc row, chips under the disc; ✕ closes', (tester) async {
    await pumpV2(
      tester,
      Builder(
        builder: (c) => TextButton(
          onPressed: () => showMgStateSheet<void>(c,
              tone: MgTone.err, title: 'Obsazenost se nepodařila načíst', chips: const [MgStateChip('Pokus 2 ze 3')]),
          child: const Text('open'),
        ),
      ),
      reducedMotion: true,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final disc = tester.getRect(find.byType(MgToneDisc));
    final close = tester.getRect(find.byType(MgV2Back));
    expect(close.center.dy, moreOrLessEquals(disc.center.dy, epsilon: 1));
    expect(close.left, greaterThan(disc.right));
    final sheetTop = tester.getTopLeft(find.byType(MgSheetFrame)).dy;
    expect(disc.top - sheetTop, lessThan(24), reason: 'no own 44 px ✕ row above the disc');
    expect(tester.getRect(find.byType(MgMeaningChip)).top, greaterThan(disc.bottom));
    await tester.tap(find.byType(MgV2Back));
    await tester.pumpAndSettle();
    expect(find.byType(MgSheetFrame), findsNothing);
  });

  testWidgets('titled sheet keeps the ✕ in its header row; other title-less sheets keep the 44 px row', (tester) async {
    await pumpV2(
      tester,
      Builder(
        builder: (c) => Column(children: [
          TextButton(
            onPressed: () => showMgSheet<void>(c, title: 'Pravidla', builder: (_) => const Text('body')),
            child: const Text('titled'),
          ),
          TextButton(
            onPressed: () => showMgSheet<void>(c, builder: (_) => const Text('plain body')),
            child: const Text('plain'),
          ),
        ]),
      ),
      reducedMotion: true,
    );
    await tester.tap(find.text('titled'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(MgV2Back)).center.dy, moreOrLessEquals(tester.getRect(find.text('Pravidla')).center.dy, epsilon: 2));
    expect(tester.getTopLeft(find.text('body')).dy, greaterThan(tester.getRect(find.byType(MgV2Back)).bottom));
    await tester.tap(find.byType(MgV2Back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('plain'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('plain body')).dy, greaterThan(tester.getRect(find.byType(MgV2Back)).bottom));
  });

  testWidgets('MgSwipeSegments: a drag moves / fades a repaint boundary, the body is not rebuilt', (tester) async {
    var builds = 0;
    var value = 'a';
    await pumpV2(
      tester,
      StatefulBuilder(
        builder: (c, set) => MgSwipeSegments<String>(
          values: const ['a', 'b'],
          value: value,
          onChanged: (v) => set(() => value = v),
          child: Builder(builder: (_) {
            builds++;
            return const SizedBox.expand(child: Text('body'));
          }),
        ),
      ),
    );
    final start = builds;
    expect(find.descendant(of: find.byType(MgSwipeSegments<String>), matching: find.byType(RepaintBoundary)), findsWidgets);
    final g = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(-10, 0));
      await tester.pump();
    }
    expect(builds, start, reason: 'drag frames only touch the fade / shift layers');
    final t = tester.widget<Transform>(find.descendant(of: find.byType(MgSwipeSegments<String>), matching: find.byType(Transform)).first);
    expect(t.transform.getTranslation().x, lessThan(0));
    await g.up();
    await tester.pumpAndSettle();
  });

  Future<List<MgPing>> funnelPings(WidgetTester tester, String state) async {
    await tester.pumpWidget(const SizedBox());
    await pumpV2(tester, const HomeScreenV2(), overrides: homeCases()[state]!(), reducedMotion: false);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 1600));
    return tester.widgetList<MgPing>(find.descendant(of: find.byType(FunnelBikeCard), matching: find.byType(MgPing))).toList();
  }

  testWidgets('Domů: recording running → the funnel "Volná v termínu" dot is static (one live indicator)', (tester) async {
    final idle = await funnelPings(tester, 's0');
    expect(idle.where((p) => p.active), isNotEmpty);
    final rec = await funnelPings(tester, 'manual-rec');
    expect(rec, isNotEmpty);
    expect(rec.where((p) => p.active), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('record row (manual recording) never splits a word at 320 dp in 8 languages, text ×1 / ×1.3', (tester) async {
    if (!montserratLoaded && Platform.environment['MG_FONTS_DIR'] == null) return; // needs real glyph widths
    for (final (lang, scale) in [for (final l in kV2Langs) for (final s in [1.0, 1.3]) (l, s)]) {
      await tester.pumpWidget(const SizedBox());
      await pumpV2(
        tester,
        Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: const SingleChildScrollView(child: HomeRecordRowV2()),
          ),
        ),
        overrides: homeCases()['manual-rec']!(),
        size: const Size(320, 690),
        lang: lang,
        reducedMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 300));
      for (final e in find.descendant(of: find.byType(HomeRecordRowV2), matching: find.byType(RichText)).evaluate()) {
        final p = e.renderObject! as RenderParagraph;
        expect(midWordBreak(p), isNull, reason: '$lang ×$scale "${p.text.toPlainText()}"');
      }
    }
  });
}
