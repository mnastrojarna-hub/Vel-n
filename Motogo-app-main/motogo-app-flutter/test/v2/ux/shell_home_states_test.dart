// SH-02 offline overlay + strip, SH-03 update dialogs, SH-43 push banner,
// SH-44 paid-after-restart toast — v2 views call exactly the old actions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_sticky_slide.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/features/shell/v2/offline_view_v2.dart';
import 'package:motogo_app/features/shell/v2/paid_toast_v2.dart';
import 'package:motogo_app/features/shell/v2/push_banner_v2.dart';
import 'package:motogo_app/features/shell/v2/update_dialog_v2.dart';

import '../render/cases_core.dart' show launcher;
import '../support/v2_harness.dart';

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('OPEN'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadMontserrat);

  testWidgets('SH-02 offline view: retry / continue / ✕ / 112 call the given actions; spinner while checking', (tester) async {
    final calls = <String>[];
    Widget view({bool checking = false}) => OfflineViewV2(
          checking: checking,
          stillOffline: false,
          onRetry: checking ? null : () => calls.add('retry'),
          onContinue: () => calls.add('continue'),
          onCall112: () => calls.add('112'),
        );
    await pumpV2(tester, view(), scaffold: false, reducedMotion: true);
    await tester.tap(find.text('Zkusit znovu'));
    await tester.tap(find.text('Pokračovat bez internetu'));
    await tester.tap(find.byKey(const ValueKey('offline-112')));
    await tester.tap(find.byType(MgV2Back));
    expect(calls, ['retry', 'continue', '112', 'continue']);
    await pumpV2(tester, view(checking: true), scaffold: false, reducedMotion: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('SH-02 strip slides down from the top once; reduced motion: at once', (tester) async {
    Widget strip(bool offline) => Stack(children: [OfflineStripV2(offline: offline)]);
    await pumpV2(tester, strip(false), scaffold: false);
    final slide = find.descendant(of: find.byType(MgStickySlide), matching: find.byType(AnimatedSlide));
    expect(tester.widget<AnimatedSlide>(slide).offset.dy, lessThan(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);
    expect(find.text('Wi‑Fi nemá internet'), findsOneWidget);

    await pumpV2(tester, strip(true), scaffold: false, reducedMotion: true);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('Jsi offline'), findsOneWidget);
  });

  testWidgets('SH-03 optional update: Později → onLater, Aktualizovat → onUpdate', (tester) async {
    final calls = <String>[];
    await pumpV2(
      tester,
      launcher((c) => showDialog<void>(
            context: c,
            builder: (ctx) => UpdateOfferDialogV2(
              version: '4.3.0',
              onLater: () {
                calls.add('later');
                Navigator.of(ctx).pop();
              },
              onUpdate: () => calls.add('update'),
            ),
          )),
    );
    await _open(tester);
    expect(find.textContaining('4.3.0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('upd-now')));
    await tester.tap(find.byKey(const ValueKey('upd-later')));
    await tester.pumpAndSettle();
    expect(calls, ['update', 'later']);
    expect(find.byType(UpdateOfferDialogV2), findsNothing);
  });

  testWidgets('SH-03 forced update survives back; update / call / 112 actions; store failure banner', (tester) async {
    final calls = <String>[];
    await pumpV2(
      tester,
      launcher((c) => showDialog<void>(
            context: c,
            barrierDismissible: false,
            builder: (_) => PopScope(
              canPop: false,
              child: UpdateForceDialogV2(
                version: '4.3.0',
                storeFailed: true,
                onUpdate: () => calls.add('update'),
                onCall: () => calls.add('call'),
                onCall112: () => calls.add('112'),
              ),
            ),
          )),
    );
    await _open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(UpdateForceDialogV2), findsOneWidget);
    expect(find.textContaining('Obchod s aplikacemi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('upd-now')));
    await tester.tap(find.byKey(const ValueKey('upd-call')));
    await tester.tap(find.byKey(const ValueKey('upd-112')));
    expect(calls, ['update', 'call', '112']);
  });

  testWidgets('SH-43 door-code push banner: key icon, Zobrazit → onView, ✕ → onClose', (tester) async {
    final calls = <String>[];
    await pumpV2(
      tester,
      launcher((c) => ScaffoldMessenger.of(c).showSnackBar(pushBannerSnackV2(
            title: 'Přístupové kódy',
            body: 'Kód motorky 4821',
            doorCodes: true,
            viewLabel: 'Zobrazit',
            closeLabel: 'Zavřít',
            onView: () => calls.add('view'),
            onClose: () => calls.add('close'),
          ))),
    );
    await _open(tester);
    expect(find.byKey(const ValueKey('push-v2-codes')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.key), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, const Duration(seconds: 8));
    await tester.tap(find.byKey(const ValueKey('push-v2-view')));
    await tester.tap(find.byKey(const ValueKey('push-v2-close')));
    expect(calls, ['view', 'close']);
    expect(tester.getSize(find.byKey(const ValueKey('push-v2-view'))).height, greaterThanOrEqualTo(44));
  });

  testWidgets('SH-43 message banner: chat icon, 2 lines, 5 s', (tester) async {
    await pumpV2(
      tester,
      launcher((c) => ScaffoldMessenger.of(c).showSnackBar(pushBannerSnackV2(
            title: 'Nová zpráva',
            body: 'A\nB\nC\nD',
            doorCodes: false,
            viewLabel: 'Zobrazit',
            closeLabel: 'Zavřít',
            onView: () {},
            onClose: () {},
          ))),
    );
    await _open(tester);
    expect(find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.chat), findsOneWidget);
    expect(tester.widget<Text>(find.text('A\nB\nC\nD')).maxLines, 2);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, const Duration(seconds: 5));
  });

  testWidgets('SH-44 paid toast reads title / message / action / duration from the payment SnackBar', (tester) async {
    var shown = 0;
    final bar = SnackBar(
      content: const Column(mainAxisSize: MainAxisSize.min, children: [Text('Motorka je obsazená'), Text('Peníze vrátíme.')]),
      duration: const Duration(seconds: 12),
      action: SnackBarAction(label: 'Zobrazit', onPressed: () => shown++),
    );
    var ok = false;
    await pumpV2(tester, launcher((c) => ok = showPaidToastV2(c, bar, failed: true)));
    await _open(tester);
    expect(ok, isTrue);
    expect(find.text('Motorka je obsazená'), findsOneWidget);
    expect(find.text('Peníze vrátíme.'), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, const Duration(seconds: 12));
    await tester.tap(find.text('Zobrazit'));
    expect(shown, 1);

    var other = true;
    await pumpV2(tester, launcher((c) => other = showPaidToastV2(c, const SnackBar(content: SizedBox()), failed: false)));
    await _open(tester);
    expect(other, isFalse);
    expect(find.byType(MgBtnText), findsNothing);
  });
}
