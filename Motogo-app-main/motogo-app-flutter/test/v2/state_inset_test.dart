// fix:state — a dock-less T1 (no primary / secondary) pads its scroll
// content by the bottom safe area (iPhone home indicator / Android gesture
// bar) and by an open keyboard, so a long screen never ends under them;
// the dock variant keeps MgDock's own inset and gets no extra padding.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/mg_dock.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/core/v2/states/mg_support_row.dart';
import 'package:motogo_app/core/v2/tokens/mg_space.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';

import 'support/v2_harness.dart';

const _kH = 780.0;
const _kBottom = 34.0; // home indicator (logical px)
const _kKeyboard = 300.0;

Widget _screen(MgTone tone, {bool dock = false}) => MgStateScreen(
      tone: tone,
      title: 'Platba se nezdařila',
      why: 'Banka platbu zamítla.',
      stepsTitle: 'Co s tím',
      steps: List.generate(14, (i) => 'Krok ${i + 1}: zkontroluj kartu a zkus to znovu.'),
      tech: 'code: card_declined · ref pi_123',
      primary: dock ? MgStateAction('Zkusit znovu', () {}) : null,
      onClose: () {},
    );

/// Pumps [child] on a 360×780 phone with the given bottom safe area /
/// keyboard, then scrolls the T1 to its end.
Future<void> _pump(WidgetTester tester, Widget child,
    {double bottom = _kBottom, double keyboard = 0, bool scaffold = false}) async {
  tester.view.padding = FakeViewPadding(bottom: bottom * 2);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
  await pumpV2(tester, child, size: const Size(360, _kH), scaffold: scaffold);
  await tester.pump(const Duration(milliseconds: 800));
  final s = tester.state<ScrollableState>(find.byType(Scrollable).first);
  s.position.jumpTo(s.position.maxScrollExtent);
  await tester.pump();
  expect(tester.takeException(), isNull);
}

double _lastBottom(WidgetTester tester) => tester.getBottomLeft(find.byType(MgSupportRow)).dy;

void main() {
  setUpAll(loadMontserrat);

  for (final tone in [MgTone.err, MgTone.ok]) {
    testWidgets('no dock ($tone): the last child clears the home indicator', (tester) async {
      await _pump(tester, _screen(tone));
      expect(find.byType(MgDock), findsNothing);
      // Scrolled to the end, the support row sits above the 34 px inset.
      expect(_lastBottom(tester), lessThanOrEqualTo(_kH - _kBottom));
    });
  }

  testWidgets('no dock: no inset → no extra padding (old geometry)', (tester) async {
    await _pump(tester, _screen(MgTone.err), bottom: 0);
    expect(_lastBottom(tester), moreOrLessEquals(_kH - MgSpace.s16, epsilon: 0.5));
  });

  testWidgets('no dock, no Scaffold: an open keyboard does not cover the end', (tester) async {
    // The platform reports padding.bottom = 0 while the keyboard is up.
    await _pump(tester, _screen(MgTone.err), bottom: 0, keyboard: _kKeyboard);
    expect(_lastBottom(tester), lessThanOrEqualTo(_kH - _kKeyboard));
  });

  testWidgets('no dock, in a Scaffold: keyboard resize + inset do not break', (tester) async {
    await _pump(tester, _screen(MgTone.err), keyboard: _kKeyboard, scaffold: true);
    expect(_lastBottom(tester), lessThanOrEqualTo(_kH - _kKeyboard - _kBottom));
  });

  for (final tone in [MgTone.err, MgTone.ok]) {
    testWidgets('dock ($tone): unchanged — MgDock pads the inset, content ends at the dock', (tester) async {
      await _pump(tester, _screen(tone, dock: true));
      expect(find.byType(MgDock), findsOneWidget);
      final dockTop = tester.getTopLeft(find.byType(MgDock)).dy;
      // Scroll content ends 16 px (its own trailing spacing) above the dock — no inset padding added.
      expect(_lastBottom(tester), moreOrLessEquals(dockTop - MgSpace.s16, epsilon: 0.5));
      // The dock's action sits above its 10 px padding + the 34 px inset.
      final action = tone == MgTone.ok ? find.byType(MgCta) : find.byType(MgBtnInk);
      expect(tester.getBottomLeft(action).dy, moreOrLessEquals(_kH - _kBottom - 10, epsilon: 0.5));
    });
  }
}
