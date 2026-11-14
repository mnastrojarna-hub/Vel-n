// R3-01: Android back while a v2 bottom sheet (showMgSheet, root navigator)
// is open over a page pushed inside the shell closes only the sheet and
// keeps the page (as the old look's sheets do) — it must not pop /booking
// (losing the filled-in form) or /sos and leave the sheet floating.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/widgets/mg_sheet.dart';

import '../support/shell_harness.dart';
import '../support/v2_harness.dart';

void main() {
  setUpAll(loadMontserrat);

  String loc(GoRouter r) => r.routerDelegate.currentConfiguration.last.matchedLocation;

  for (final path in ['/booking', '/sos']) {
    testWidgets('R3-01: back with a sheet open on $path closes only the sheet', (t) async {
      final router = await pumpShellV2(t, '/', paths: [...kShellTestPaths, '/booking']);
      router.push(path);
      await t.pumpAndSettle();
      expect(loc(router), path);
      final ctx = t.element(find.text('PAGE $path'));
      showMgSheet<void>(ctx, title: 'Kód', builder: (_) => const Text('SHEET BODY'));
      await t.pumpAndSettle();
      expect(find.text('SHEET BODY'), findsOneWidget);

      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('SHEET BODY'), findsNothing, reason: 'back closes the sheet');
      expect(loc(router), path, reason: 'the page under the sheet stays');
      expect(find.text('PAGE $path'), findsOneWidget);

      // A second back now leaves the page as before (no sheet left).
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(loc(router), '/');
    });
  }

  testWidgets('R3-01: a dialog over the sheet closes first, then the sheet', (t) async {
    final router = await pumpShellV2(t, '/', paths: [...kShellTestPaths, '/booking']);
    router.push('/booking');
    await t.pumpAndSettle();
    final ctx = t.element(find.text('PAGE /booking'));
    showMgSheet<void>(ctx, title: 'Kód', builder: (_) => const Text('SHEET BODY'));
    await t.pumpAndSettle();
    showDialog<void>(context: t.element(find.text('SHEET BODY')), useRootNavigator: true, builder: (_) => const AlertDialog(content: Text('DIALOG')));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('DIALOG'), findsNothing);
    expect(find.text('SHEET BODY'), findsOneWidget);
    expect(loc(router), '/booking');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('SHEET BODY'), findsNothing);
    expect(loc(router), '/booking');
  });
}
