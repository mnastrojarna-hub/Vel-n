// Kill-switch OFF guarantee (PLAN §3.3): with `MgV2Scope(enabled: false)` —
// or no scope at all, as in the pre-existing suite — every V-seam returns
// the OLD widget tree; no v2 widget is built.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_dialog.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';
import 'package:motogo_app/core/widgets/route_error_page.dart';
import 'package:motogo_app/core/widgets/state_views.dart';

import 'support/v2_harness.dart';

void main() {
  for (final v2 in [false, true]) {
    testWidgets('route error page (v2=$v2)', (tester) async {
      final router = GoRouter(
        initialLocation: '/nope',
        routes: [GoRoute(path: '/', builder: (_, __) => const Text('HOME'))],
        errorBuilder: (_, s) => RouteErrorPage(state: s),
      );
      tester.view.physicalSize = const Size(720, 1560);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: v2TestTheme(),
        builder: (c, child) => MgV2Scope(enabled: v2, child: child!),
      ));
      await tester.pump();
      expect(find.byType(MgStateScreen), v2 ? findsOneWidget : findsNothing);
      expect(find.byType(MgStateScaffold), v2 ? findsNothing : findsOneWidget);
      expect(find.byType(AppBar), v2 ? findsNothing : findsOneWidget);
    });

    testWidgets('showErrorDialog (v2=$v2)', (tester) async {
      String? picked;
      await pumpV2(tester, Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async => picked = await showErrorDialog(context,
              title: 'Platba neprošla', body: 'Zkus jinou kartu.', actions: const [('retry', 'Zkusit znovu')]),
          child: const Text('open'),
        );
      }), v2: v2);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), v2 ? findsNothing : findsOneWidget);
      expect(find.byType(MgDialogFrame), v2 ? findsOneWidget : findsNothing);
      await tester.tap(find.text('Zkusit znovu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(picked, 'retry');
    });
  }

  testWidgets('no scope at all = old UI (pre-existing suite)', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MgBackArrow(onTap: () {}))));
    expect(find.byType(MgV2Back), findsNothing);
  });
}
