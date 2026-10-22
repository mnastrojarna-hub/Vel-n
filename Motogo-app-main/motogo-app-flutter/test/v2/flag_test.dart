// Kill-switch `app_v2_ui` (PLAN §3): row absent / true → ON, false → OFF,
// fetch error → last cached value; a change never lands mid-payment or
// inside a focused flow — only on a tab root (or at the next cold start).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('preload: no pref → ON; stored false → OFF', () async {
    await AppV2UiNotifier.preload();
    expect(AppV2UiNotifier.bootValue, isTrue);
    SharedPreferences.setMockInitialValues({AppV2UiNotifier.prefKey: false});
    await AppV2UiNotifier.preload();
    expect(AppV2UiNotifier.bootValue, isFalse);
    AppV2UiNotifier.bootValue = true;
  });

  test('remote OFF is stored for the next cold start and waits for a safe moment', () async {
    var paying = false;
    final n = AppV2UiNotifier(
      fetch: () async => false,
      paymentRunning: () => paying,
      autoRefresh: false,
      initial: true,
    );
    await n.refresh();
    expect(n.state, isTrue, reason: 'never switched immediately');
    expect(n.pending, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppV2UiNotifier.prefKey), isFalse);

    expect(n.applyPendingIfSafe('/booking'), isFalse, reason: 'focused flow');
    expect(n.applyPendingIfSafe('/reservations/abc'), isFalse, reason: 'not a tab root');
    paying = true;
    expect(n.applyPendingIfSafe('/'), isFalse, reason: 'payment running');
    paying = false;
    expect(n.applyPendingIfSafe('/reservations?x=1'), isTrue);
    expect(n.state, isFalse);
    expect(n.pending, isNull);
  });

  test('fetch error / offline (null) keeps the current value', () async {
    final n = AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: false);
    await n.refresh();
    expect(n.state, isFalse);
    expect(n.pending, isNull);
  });

  test('same remote value → nothing pending', () async {
    final n = AppV2UiNotifier(fetch: () async => true, autoRefresh: false, initial: true);
    await n.refresh();
    expect(n.pending, isNull);
    expect(n.applyPendingIfSafe('/'), isFalse);
  });

  test('every tab root is a safe point', () {
    for (final r in kV2TabRoots) {
      final n = AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)..pending = false;
      expect(n.applyPendingIfSafe(r), isTrue, reason: r);
    }
  });

  testWidgets('MgV2Scope: no scope = OFF (old UI), V2Switch picks exactly one', (tester) async {
    late bool seen;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (c) {
        seen = MgV2.on(c);
        return const V2Switch(v1: Text('OLD'), v2: Text('NEW'));
      }),
    ));
    expect(seen, isFalse);
    expect(find.text('OLD'), findsOneWidget);
    expect(find.text('NEW'), findsNothing);

    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: MgV2Scope(enabled: true, child: V2Switch(v1: Text('OLD'), v2: Text('NEW'))),
    ));
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('OLD'), findsNothing);
  });
}
