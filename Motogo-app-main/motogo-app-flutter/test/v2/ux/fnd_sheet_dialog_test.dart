// FND-5 sheet pull-to-dismiss + motion, FND-6 dialogs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_dialog.dart';
import 'package:motogo_app/core/v2/widgets/mg_sheet.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';

Widget _app(void Function(BuildContext) open, {TargetPlatform platform = TargetPlatform.android, bool reduced = false}) =>
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (c, child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduced), child: child!),
      ),
      home: Scaffold(body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => open(c), child: const Text('open'))))),
    );

Widget _rows() => Column(children: [for (var i = 0; i < 40; i++) SizedBox(height: 48, child: Text('row $i'))]);

Future<void> _openSheet(WidgetTester tester, {TargetPlatform platform = TargetPlatform.android, bool reduced = false,
    bool enableDrag = true, Widget Function()? body}) async {
  tester.view.physicalSize = const Size(360, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(
    (c) => showMgSheet<void>(c, title: 'Sheet', enableDrag: enableDrag, builder: (_) => (body ?? _rows)()),
    platform: platform,
    reduced: reduced,
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('row 2'), findsOneWidget);
}

double _pull(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(const ValueKey('mg-sheet-pull'))).transform.getTranslation().y;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('FND-5 sheet ${platform.name}', () {
      testWidgets('pull ↓300 at the top → closes', (tester) async {
        await _openSheet(tester, platform: platform);
        await tester.timedDrag(find.text('row 2'), const Offset(0, 300), const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text('row 2'), findsNothing);
      });

      testWidgets('pull ↓40 → stays, springs back to 0', (tester) async {
        await _openSheet(tester, platform: platform);
        final g = await tester.startGesture(tester.getCenter(find.text('row 2')));
        for (var i = 0; i < 8; i++) {
          await g.moveBy(const Offset(0, 8));
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(_pull(tester), greaterThan(0));
        await g.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 320));
        expect(find.text('row 2'), findsOneWidget);
        expect(_pull(tester), 0);
      });

      testWidgets('scrolled to the middle, ↓200 only scrolls', (tester) async {
        await _openSheet(tester, platform: platform);
        await tester.timedDrag(find.text('row 6'), const Offset(0, -700), const Duration(milliseconds: 900));
        await tester.pumpAndSettle();
        final pos = tester.state<ScrollableState>(find.descendant(of: find.byType(MgSheetFrame), matching: find.byType(Scrollable))).position;
        final before = pos.pixels;
        expect(before, greaterThan(400));
        await tester.timedDrag(find.text('row 22'), const Offset(0, 200), const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        expect(find.byType(MgSheetFrame), findsOneWidget);
        expect(pos.pixels, lessThan(before));
      });

      testWidgets('PopScope(canPop: false) keeps it open and is asked', (tester) async {
        var asked = 0;
        await _openSheet(tester, platform: platform, body: () => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) => asked++,
              child: _rows(),
            ));
        await tester.timedDrag(find.text('row 2'), const Offset(0, 300), const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text('row 2'), findsOneWidget);
        expect(asked, greaterThanOrEqualTo(1));
        expect(_pull(tester), 0);
      });

      testWidgets('enableDrag: false → a body pull never closes', (tester) async {
        await _openSheet(tester, platform: platform, enableDrag: false);
        await tester.timedDrag(find.text('row 2'), const Offset(0, 300), const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text('row 2'), findsOneWidget);
      });
    });
  }

  testWidgets('FND-5 reduced motion: no follow, closes on release without frames between', (tester) async {
    await _openSheet(tester, reduced: true);
    final g = await tester.startGesture(tester.getCenter(find.text('row 2')));
    for (var i = 0; i < 15; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 30));
      expect(_pull(tester), 0);
    }
    await g.up();
    await tester.pump();
    await tester.pump();
    expect(find.text('row 2'), findsNothing);
  });

  group('FND-6 dialogs', () {
    Future<bool?> confirm(WidgetTester tester, Future<void> Function() act, {bool reduced = false}) async {
      bool? out = false;
      var done = false;
      await tester.pumpWidget(_app(
        (c) => showMgConfirm(c, title: 'Zrušit?', safeLabel: 'Zůstat', actionLabel: 'Zrušit').then((v) {
          out = v;
          done = true;
        }),
        reduced: reduced,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      expect(done, isTrue);
      return out;
    }

    testWidgets('confirm returns true / false / null as before', (tester) async {
      expect(await confirm(tester, () => tester.tap(find.text('Zrušit').last)), isTrue);
      expect(await confirm(tester, () => tester.tap(find.text('Zůstat'))), isFalse);
      expect(await confirm(tester, () => tester.tapAt(const Offset(10, 10))), isNull);
    });

    for (final reduced in [false, true]) {
      testWidgets('dialog scales .96 → 1 mid-animation; reduced=$reduced → none', (tester) async {
        await tester.pumpWidget(_app(
          (c) => showMgConfirm(c, title: 'T', safeLabel: 'S', actionLabel: 'A'),
          reduced: reduced,
        ));
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final scales = tester
            .widgetList<ScaleTransition>(find.ancestor(of: find.byType(MgDialogFrame), matching: find.byType(ScaleTransition)))
            .where((s) => s.scale.value < 1);
        expect(scales.isNotEmpty, !reduced);
        await tester.pumpAndSettle();
        expect(find.byType(MgDialogFrame), findsOneWidget);
      });
    }

    testWidgets('error dialog: one ink, then ghost, close as text; no emoji', (tester) async {
      String? picked = 'none';
      await tester.pumpWidget(_app((c) async {
        picked = await showErrorDialog(c, title: '⚠️ Platba neprošla', body: 'Zkus to znovu 🙂.', actions: [('retry', '✓ Zkusit znovu'), ('other', 'Jiná karta')]);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(MgBtnInk), findsOneWidget);
      expect(find.byType(MgBtnGhostLight), findsOneWidget);
      expect(find.byType(MgBtnText), findsOneWidget);
      expect(find.text('Platba neprošla'), findsOneWidget);
      expect(find.text('Zkus to znovu.'), findsOneWidget);
      expect(find.text('Zkusit znovu'), findsOneWidget);
      await tester.tap(find.text('Jiná karta'));
      await tester.pumpAndSettle();
      expect(picked, 'other');
    });
  });
}
