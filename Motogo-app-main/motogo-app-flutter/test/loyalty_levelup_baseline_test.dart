// Baseline „už oslaveno": max(server, lokální značka). Selhání zápisu ani
// čtení nesmí vést k druhé oslavě téhož levelu ani ke spolknutí povýšení;
// přepnutí účtu během čekání nic nezapíše.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/loyalty/loyalty_levelup_baseline.dart';

import 'loyalty_levelup_rig.dart';

/// Počet dotazů na server po úvodních kontrolách (start appky jich udělá 1–2).
Future<int> _settledCalls(WidgetTester t) async {
  await settle(t, 2000);
  return fake.getCalls;
}

void main() {
  setUp(() => fake = FakeLoyalty());

  group('decideLevelUp', () {
    LevelUpDecision d(int level, CelebratedRead server, {int? marker, int? legacy}) =>
        decideLevelUp(level: level, server: server, marker: marker, legacy: legacy);
    const unknown = CelebratedRead.unknown();
    const missing = CelebratedRead.missing();

    test('server known: baseline = max(server, marker)', () {
      expect(d(4, const CelebratedRead.value(3)).action, LevelUpAction.celebrate);
      expect(d(5, const CelebratedRead.value(3)).gained, 2);
      expect(d(4, const CelebratedRead.value(4)).action, LevelUpAction.none);
      expect(d(3, const CelebratedRead.value(4)).action, LevelUpAction.none);
      // celebrated here, the server write failed → no second celebration
      expect(d(4, const CelebratedRead.value(3), marker: 4).action, LevelUpAction.none);
      expect(d(5, const CelebratedRead.value(3), marker: 4).gained, 1);
      // a stale legacy key never decides while the server answers
      expect(d(5, const CelebratedRead.value(5), legacy: 3).action, LevelUpAction.none);
    });

    test('first observation seeds; a failed seed write does not swallow the next level-up', () {
      expect(d(2, const CelebratedRead.value(0)).action, LevelUpAction.seed);
      expect(d(3, const CelebratedRead.value(0), marker: 2).action, LevelUpAction.celebrate);
      expect(d(2, const CelebratedRead.value(0), marker: 2).action, LevelUpAction.none);
    });

    test('server unknown: never celebrate from local data, never write', () {
      expect(d(4, unknown).action, LevelUpAction.unknown);
      expect(d(4, unknown, marker: 3).action, LevelUpAction.unknown);
      expect(d(5, unknown, legacy: 3).action, LevelUpAction.unknown, reason: 'could be celebrated on another phone');
      expect(d(4, unknown, marker: 4).action, LevelUpAction.none, reason: 'nothing to celebrate either way');
    });

    test('RPC missing in the database: the original local rule', () {
      expect(d(4, missing).action, LevelUpAction.seed);
      expect(d(4, missing, legacy: 3).gained, 1);
      expect(d(4, missing, legacy: 4).action, LevelUpAction.none);
      expect(d(4, missing, legacy: 3, marker: 4).action, LevelUpAction.none);
    });
  });

  testWidgets('first observation of an account (server 0): seeded silently', (t) async {
    fake
      ..level = 3
      ..celebrated = 0;
    await boot(t);
    await settle(t);
    await t.pump(const Duration(seconds: 5));
    expect(celebration, findsNothing);
    expect(fake.advances, [3]);
    expect(prefs.getInt(markerKey(uidA)), 3);
    await unmount(t);
  });

  testWidgets('seed write fails → the next level-up is still celebrated (not swallowed)', (t) async {
    fake
      ..level = 2
      ..celebrated = 0
      ..failAdvance = true;
    await boot(t);
    await settle(t);
    expect(celebration, findsNothing);
    expect(fake.celebrated, 0, reason: 'the server never got the seed');
    expect(prefs.getInt(markerKey(uidA)), 2);

    fake
      ..level = 3
      ..failAdvance = false;
    await recheck(t);
    expect(celebration, findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(fake.advances, [2, 3], reason: 'seed re-sent, then the celebrated level');
    await unmount(t);
  });

  testWidgets('server advance fails after the show → no second celebration; the write is retried', (t) async {
    fake
      ..level = 4
      ..celebrated = 3
      ..failAdvance = true;
    await boot(t);
    await settle(t);
    expect(celebration, findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(celebration, findsNothing);
    expect(fake.celebrated, 3, reason: 'the server write failed');
    expect(prefs.getInt(markerKey(uidA)), 4);

    await recheck(t);
    await t.pump(const Duration(seconds: 10));
    expect(celebration, findsNothing, reason: 'no duplicate while the server is behind');

    fake.failAdvance = false;
    await recheck(t);
    expect(celebration, findsNothing);
    expect(fake.advances, [4], reason: 'retried until it succeeded');
    await recheck(t);
    expect(fake.advances, [4], reason: 'in sync → no further writes');
    await unmount(t);
  });

  testWidgets('get-celebrated fails: a stale local key alone never celebrates (no duplicate)', (t) async {
    fake
      ..level = 5
      ..celebrated = 5 // already celebrated on another phone
      ..failGet = true;
    await boot(t, initialPrefs: {legacyKey(uidA): 3});
    await settle(t, 30000); // including the automatic retries
    expect(celebration, findsNothing);
    expect(fake.advances, isEmpty);
    expect(prefs.getInt(markerKey(uidA)), isNull);
    expect(prefs.getInt(legacyKey(uidA)), 3, reason: 'nothing written while the baseline is unknown');

    fake.failGet = false;
    await recheck(t);
    expect(celebration, findsNothing);
    await unmount(t);
  });

  testWidgets('get-celebrated fails: a pending level-up is not swallowed — shown once when the server answers', (t) async {
    fake
      ..level = 4
      ..celebrated = 3
      ..failGet = true;
    await boot(t);
    await settle(t);
    expect(celebration, findsNothing);
    expect(prefs.getInt(markerKey(uidA)), isNull);
    expect(prefs.getInt(legacyKey(uidA)), isNull);

    fake.failGet = false;
    await t.pump(const Duration(seconds: 5)); // the short automatic retry, no touch
    await settle(t);
    expect(celebration, findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(fake.advances, [4]);
    await recheck(t);
    expect(celebration, findsNothing);
    await unmount(t);
  });

  testWidgets('get-celebrated keeps failing: at most 3 quick retries, then the normal rhythm', (t) async {
    fake
      ..level = 4
      ..celebrated = 3
      ..failGet = true;
    await boot(t);
    final first = await _settledCalls(t);
    await settle(t, 60000);
    final calls = fake.getCalls;
    expect(calls, first + 3, reason: 'exactly 3 quick retries');
    await settle(t, 60000);
    expect(fake.getCalls, calls, reason: 'no polling loop during an outage');
    expect(celebration, findsNothing);

    fake.failGet = false;
    await recheck(t);
    expect(celebration, findsOneWidget);
    await unmount(t);
  });

  testWidgets('account switch while the server is being asked → nothing shown, nothing written', (t) async {
    fake
      ..level = 4
      ..celebrated = 3
      ..getGate = Completer<void>();
    await boot(t);
    await settle(t, 300);
    expect(fake.getCalls, 1, reason: 'the check for account A is waiting for the server');
    await loginAs(t, uidB);
    fake.getGate!.complete();
    fake.getGate = null;
    await settle(t);
    await t.pump(const Duration(seconds: 3));
    expect(celebration, findsNothing);
    expect(fake.advances, isEmpty, reason: "A's level must never reach B's profile");
    for (final uid in [uidA, uidB]) {
      expect(prefs.getInt(markerKey(uid)), isNull);
      expect(prefs.getInt(legacyKey(uid)), isNull);
    }
    await unmount(t);
  });

  testWidgets('account switch while the media is loading → no celebration for the old account', (t) async {
    fake
      ..level = 4
      ..celebrated = 3
      ..motosGate = Completer<void>();
    await boot(t);
    await settle(t, 300);
    await loginAs(t, uidB);
    fake.motosGate!.complete();
    fake.motosGate = null;
    await settle(t);
    await t.pump(const Duration(seconds: 3));
    expect(celebration, findsNothing);
    expect(fake.advances, isEmpty);
    expect(prefs.getInt(markerKey(uidA)), isNull);
    expect(prefs.getInt(markerKey(uidB)), isNull);
    await unmount(t);
  });

  testWidgets('RPC missing in the database → original local mode still celebrates once', (t) async {
    fake
      ..level = 4
      ..rpcMissing = true;
    await boot(t, initialPrefs: {legacyKey(uidA): 3});
    await settle(t);
    expect(celebration, findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await tapContinue(t);
    expect(prefs.getInt(legacyKey(uidA)), 4);
    expect(prefs.getInt(markerKey(uidA)), 4);
    await recheck(t);
    expect(celebration, findsNothing);
    await unmount(t);
  });
}
