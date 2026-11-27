// Level-up oslava se počítá jako „oslavená" JEN když ji zákazník sám ukončil
// tlačítkem (nebo systémovým zpět, až je tlačítko vidět) nebo doběhla do
// konce. Cokoli jiného (cizí pop, přesměrování) = neviděl → přehraje se znovu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/main.dart' show rootNavigatorKey;

import 'loyalty_levelup_rig.dart';

void main() {
  setUp(() => fake = FakeLoyalty());

  testWidgets('happy path: shown once, written only after the customer ends it', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t);
    await settle(t);
    expect(celebration, findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    expect(fake.advances, isEmpty, reason: 'nothing is written while it plays');
    expect(prefs.getInt(markerKey(uidA)), isNull);
    await tapContinue(t);
    expect(celebration, findsNothing);
    expect(fake.advances, [4]);
    expect(prefs.getInt(markerKey(uidA)), 4);
    await recheck(t);
    await t.pump(const Duration(seconds: 10));
    expect(celebration, findsNothing, reason: 'exactly once');
    expect(fake.advances, [4]);
    await unmount(t);
  });

  testWidgets('several levels at once (new device, no local data): one celebration with +N', (t) async {
    fake
      ..level = 5
      ..celebrated = 3;
    await boot(t);
    await settle(t);
    expect(celebration, findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(fake.advances, [5]);
    await recheck(t);
    expect(celebration, findsNothing);
    await unmount(t);
  });

  testWidgets('reduced motion keeps the full 67 s (no 3-second show counted as seen)', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t);
    await settle(t);
    expect(celebration, findsOneWidget);
    await t.pump(const Duration(seconds: 60));
    expect(celebration, findsOneWidget, reason: 'still playing after a minute');
    expect(fake.advances, isEmpty);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await settle(t);
    expect(celebration, findsNothing, reason: 'natural end at 67 s');
    expect(fake.advances, [4]);
    await unmount(t);
  });

  testWidgets('the Continue button does nothing while it is invisible', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t);
    await settle(t, 400);
    expect(celebration, findsOneWidget);
    await t.tap(find.text('Pokračovat'), warnIfMissed: false);
    await settle(t);
    expect(celebration, findsOneWidget);
    expect(fake.advances, isEmpty);
    expect(prefs.getInt(markerKey(uidA)), isNull);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(celebration, findsNothing);
    expect(fake.advances, [4]);
    await unmount(t);
  });

  testWidgets('system Back: nothing before the button is visible, then it equals the button', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t);
    await settle(t, 400);
    expect(celebration, findsOneWidget);
    await t.binding.handlePopRoute();
    await settle(t);
    expect(celebration, findsOneWidget, reason: 'Back before the button does nothing');
    expect(fake.advances, isEmpty);
    await t.pump(const Duration(seconds: 6));
    await t.binding.handlePopRoute();
    await settle(t);
    expect(celebration, findsNothing);
    expect(fake.advances, [4]);
    await recheck(t);
    expect(celebration, findsNothing);
    await unmount(t);
  });

  testWidgets('a foreign pop removes it → not counted, it replays by itself and then counts once', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t);
    await settle(t, 400);
    expect(celebration, findsOneWidget);
    final first = t.state(celebration);
    rootNavigatorKey.currentState!.pop(); // e.g. `context.pop()` after an awaited save
    await settle(t, 400);
    expect(celebration, findsNothing);
    expect(fake.advances, isEmpty, reason: 'not seen → nothing written');
    expect(prefs.getInt(markerKey(uidA)), isNull);
    expect(prefs.getInt(legacyKey(uidA)), isNull);
    await settle(t, 2000);
    expect(celebration, findsOneWidget, reason: 'replayed without any touch');
    expect(t.state(celebration), isNot(same(first)));
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(fake.advances, [4]);
    await t.pump(const Duration(seconds: 10));
    await recheck(t);
    expect(celebration, findsNothing);
    await unmount(t);
  });

  testWidgets('router.go across the shell while it plays → not counted, replays on the new page', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t);
    await settle(t);
    expect(celebration, findsOneWidget);
    final first = t.state(celebration);
    router.go('/out'); // root page under the dialog is replaced → dialog removed with it
    await settle(t, 2500);
    expect(find.textContaining('OUT', skipOffstage: false), findsOneWidget);
    expect(celebration, findsOneWidget, reason: 'replayed on the new page');
    expect(t.state(celebration), isNot(same(first)), reason: 'the first one was removed');
    expect(fake.advances, isEmpty, reason: 'the removed one was not counted');
    expect(prefs.getInt(markerKey(uidA)), isNull);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(fake.advances, [4]);
    await unmount(t);
  });

  testWidgets('natural end closes only its OWN route (a blocking dialog above stays)', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t);
    await settle(t);
    expect(celebration, findsOneWidget);
    showDialog<void>(
      context: rootNavigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: AlertDialog(title: Text('FORCE UPDATE'))),
    );
    await settle(t);
    expect(find.text('FORCE UPDATE'), findsOneWidget);
    // Back belongs to the dialog above (which blocks it) — the celebration stays.
    await t.pump(const Duration(seconds: 6));
    await t.binding.handlePopRoute();
    await settle(t);
    expect(celebration, findsOneWidget);
    expect(find.text('FORCE UPDATE'), findsOneWidget);
    for (var i = 0; i < 64; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await settle(t);
    expect(find.text('FORCE UPDATE'), findsOneWidget, reason: 'the dialog above is not popped');
    expect(celebration, findsNothing);
    expect(fake.advances, [4], reason: 'ran to its natural end');
    await unmount(t);
  });
}
