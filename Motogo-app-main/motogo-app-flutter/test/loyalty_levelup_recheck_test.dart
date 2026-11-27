// Kdy se rank zkontroluje: hned po skončení blokace (intro / jazyk /
// oprávnění při startu, platební obrazovka), po návratu do popředí, při
// změně rezervací a tříminutovou pojistkou. Blokovaná kontrola nic nezapíše.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';

import 'loyalty_levelup_rig.dart';

void main() {
  setUp(() => fake = FakeLoyalty());

  testWidgets('cold start under the intro overlay: nothing written, shown as soon as the overlay ends', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    final res = StreamController<List<Reservation>>();
    await boot(t, overlay: true, reservations: res.stream);
    await settle(t);
    res.add(const []); // reservations loaded → forced check (stamps the 45 s touch throttle)
    await settle(t);
    await t.pump(const Duration(seconds: 2));
    expect(celebration, findsNothing, reason: 'the overlay would cover it');
    expect(fake.advances, isEmpty);
    expect(prefs.getInt(markerKey(uidA)), isNull);
    expect(prefs.getInt(legacyKey(uidA)), isNull);

    container.read(onboardingOverlayActiveProvider.notifier).state = false; // intro finished
    await settle(t);
    expect(celebration, findsOneWidget, reason: 'no touch and no 45 s wait needed');
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(fake.advances, [4]);
    await res.close();
    await unmount(t);
  });

  testWidgets('payment screen: deferred without a write, shown as soon as payment is left', (t) async {
    fake
      ..level = 4
      ..celebrated = 3;
    await boot(t, payment: true);
    await settle(t);
    await t.pump(const Duration(seconds: 5));
    expect(celebration, findsNothing);
    expect(fake.advances, isEmpty);
    expect(prefs.getInt(markerKey(uidA)), isNull);

    container.read(paymentScreenActiveProvider.notifier).state = false;
    await settle(t);
    expect(celebration, findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(fake.advances, [4]);
    await unmount(t);
  });

  testWidgets('a block that ends with nothing pending shows nothing', (t) async {
    fake
      ..level = 3
      ..celebrated = 3;
    await boot(t, overlay: true);
    await settle(t);
    container.read(onboardingOverlayActiveProvider.notifier).state = false;
    await settle(t);
    await t.pump(const Duration(seconds: 5));
    expect(celebration, findsNothing);
    expect(fake.advances, isEmpty);
    await unmount(t);
  });

  testWidgets('level rises while the app is in background → shown on resume', (t) async {
    fake
      ..level = 3
      ..celebrated = 3;
    await boot(t);
    await settle(t);
    expect(celebration, findsNothing);
    for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      t.binding.handleAppLifecycleStateChanged(st);
    }
    fake.level = 4;
    await t.pump(const Duration(seconds: 2));
    for (final st in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      t.binding.handleAppLifecycleStateChanged(st);
    }
    await settle(t);
    expect(celebration, findsOneWidget);
    await unmount(t);
  });

  testWidgets('level rises while the app is open: reservations change → immediate check', (t) async {
    fake
      ..level = 3
      ..celebrated = 3;
    final res = StreamController<List<Reservation>>();
    await boot(t, reservations: res.stream);
    res.add(const []);
    await settle(t);
    expect(celebration, findsNothing);
    fake.level = 4;
    res.add(<Reservation>[]); // booking completed → realtime → new list
    await settle(t);
    expect(celebration, findsOneWidget);
    await res.close();
    await unmount(t);
  });

  testWidgets('level rises while the app is open and untouched → 3-minute timer (+2 = one show)', (t) async {
    fake
      ..level = 3
      ..celebrated = 3;
    await boot(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    expect(celebration, findsNothing);
    fake.level = 5;
    await t.pump(const Duration(seconds: 170));
    expect(celebration, findsNothing);
    await t.pump(const Duration(seconds: 12));
    await settle(t);
    expect(celebration, findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    await unmount(t);
  });

  testWidgets('offline start: nothing shown or written; shown on the next check once online', (t) async {
    fake
      ..level = 4
      ..celebrated = 3
      ..failStatus = true;
    await boot(t);
    await settle(t);
    expect(celebration, findsNothing);
    expect(fake.advances, isEmpty);
    expect(prefs.getInt(markerKey(uidA)), isNull);
    fake.failStatus = false;
    resetLoyaltyPollClock(); // = 45 s since the last touch check
    await t.tapAt(const Offset(100, 100));
    await settle(t);
    expect(celebration, findsOneWidget);
    await unmount(t);
  });
}
