// fix:r2:areas (b) — surfaces that were still the old look inside v2, now
// v2 views over the SAME data, conditions, texts and closures: "Historie
// rezervace", the edit add-ons ("Výbava a doplňky") and "Žebříček jezdců"
// (flag loyalty_leaderboard); the old look of each stays unchanged.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';
import 'package:motogo_app/features/loyalty/loyalty_leaderboard_section.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/loyalty/v2/loyalty_leaderboard_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_extras_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_history_v2.dart';
import 'package:motogo_app/features/reservations/widgets/res_modification_history.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_extras_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_history.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_leaderboard.dart';
import '../support/fakes_reservations.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

/// The flag, then the board data (watched only once the flag is on).
Future<void> _lb(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  group('Historie rezervace in the v2 look', () {
    testWidgets('v2: the same blocks and texts, no emoji, no old palette', (t) async {
      await pumpV2(t, SingleChildScrollView(child: ResModificationHistory(res: histModsRes())),
          overrides: resOverrides(), reducedMotion: true);
      expect(find.byType(ResHistoryV2), findsOneWidget);
      expect(find.textContaining('📋'), findsNothing);
      expect(find.text('${_t('modificationHistory')} (2×)'), findsOneWidget);
      expect(find.text(_t('reservationTimeline')), findsOneWidget);
      expect(find.text(_t('originalTerm')), findsOneWidget);
      expect(find.text(_t('newTerm')), findsOneWidget);
      expect(find.text(_t('histExtrasChanged')), findsOneWidget);
      expect(find.textContaining('Husqvarna 701 SM', findRichText: true), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('v2: cancelled + SOS keeps the SOS and storno blocks', (t) async {
      await pumpV2(
          t, SingleChildScrollView(child: ResModificationHistory(res: histCancelSosRes(), sosIncidents: histIncidents())),
          overrides: resOverrides(), reducedMotion: true);
      expect(find.text(_t('sosEvents')), findsOneWidget);
      expect(find.text(_t('replacementForSos')), findsOneWidget);
      expect(find.textContaining(_t('endedBySos')), findsOneWidget);
      expect(find.text(_t('cancellationSection')), findsOneWidget);
      expect(find.text('Pád v zatáčce, poškozená páčka'), findsOneWidget);
      expect(find.text('#AB12CD34'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('flag OFF: the old widget unchanged', (t) async {
      await pumpV2(t, SingleChildScrollView(child: ResModificationHistory(res: histModsRes())),
          overrides: resOverrides(), v2: false);
      expect(find.byType(ResHistoryV2), findsNothing);
      expect(find.text('📋'), findsOneWidget);
    });
  });

  group('edit "Výbava a doplňky": add-ons in the v2 look, same closures', () {
    Widget section(List<String> log, {Set<String> sel = const {}, int level = 0, String pickup = 'store'}) => EditExtrasSection(
          selectedExtras: sel,
          pickupMethod: pickup,
          returnMethod: 'store',
          loyaltyLevel: level,
          helmetSize: 'L', jacketSize: 'XL', pantsSize: null, bootsSize: null, glovesSize: 'L',
          passengerHelmetSize: 'M', passengerJacketSize: null, passengerPantsSize: null, passengerBootsSize: null,
          onPassengerGlovesSize: (v) => log.add('pgloves:$v'),
          onExtrasChanged: (e) => log.add('extras:${(e.toList()..sort()).join(',')}'),
          onOwnGearChanged: (v) => log.add('own:$v'),
          onHelmetSize: (_) {}, onJacketSize: (_) {}, onPantsSize: (_) {}, onBootsSize: (v) => log.add('boots:$v'),
          onGlovesSize: (_) {},
          onPassengerHelmetSize: (v) => log.add('phelmet:$v'),
          onPassengerJacketSize: (v) => log.add('pjacket:$v'),
          onPassengerPantsSize: (v) => log.add('ppants:$v'),
          onPassengerBootsSize: (_) {},
        );

    testWidgets('three add-on rows, delivery note, rank line; no Material checkbox, no emoji', (t) async {
      await pumpV2(t, SingleChildScrollView(child: section([], level: 3, pickup: 'delivery')),
          overrides: resOverrides(), reducedMotion: true);
      expect(find.byType(EditAddonsV2), findsOneWidget);
      expect(find.byType(BookingExtraRowV2), findsNWidgets(3));
      expect(find.text(_t('deliverySizeInfo')), findsOneWidget);
      expect(find.text(_t('loyaltyGearBenefit')), findsOneWidget);
      expect(find.text(_t('gearFree')), findsNWidgets(3));
      expect(find.textContaining('🏅'), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('unselected passenger row: add + its size sheet (old closure)', (t) async {
      final log = <String>[];
      await pumpV2(t, SingleChildScrollView(child: section(log)), overrides: resOverrides(), reducedMotion: true);
      expect(find.text('+690\u00A0Kč'), findsOneWidget);
      await t.tap(find.text(_t('passengerGearLabel')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(log, ['extras:spolujezdec']);
    });

    testWidgets('selected passenger row: remove + clear the passenger sizes (old closure)', (t) async {
      final log = <String>[];
      await pumpV2(t, SingleChildScrollView(child: section(log, sel: {'spolujezdec'})),
          overrides: resOverrides(), reducedMotion: true);
      await t.tap(find.text(_t('passengerGearLabel')).first);
      await t.pump();
      expect(log, ['extras:', 'phelmet:null', 'pjacket:null', 'ppants:null', 'pgloves:null']);
      // The inline passenger sizes stay as before (label in the v2 look).
      expect(find.byType(EditPassengerLabelV2), findsOneWidget);
    });

    testWidgets('flag OFF: the old cards unchanged', (t) async {
      await pumpV2(t, SingleChildScrollView(child: section([], level: 3)), overrides: resOverrides(), v2: false);
      expect(find.byType(EditAddonsV2), findsNothing);
      expect(find.text('🏅'), findsOneWidget);
      expect(find.text(_t('gearFree').toUpperCase()), findsNWidgets(3));
    });
  });

  group('Žebříček jezdců (flag loyalty_leaderboard) in the v2 look', () {
    Widget page() => const ColoredBox(
        color: Color(0xFF0B1410), child: SingleChildScrollView(child: LoyaltyLeaderboardSection()));

    testWidgets('v2: same texts, podium + list, winner, opt-in; no emoji', (t) async {
      await pumpV2(t, page(), overrides: leaderboardOverrides(), reducedMotion: true);
      await _lb(t);
      expect(find.byType(LoyaltyLeaderboardV2), findsOneWidget);
      expect(find.text(_t('loyaltyLeaderboardTitle')), findsOneWidget);
      expect(find.text(_t('loyaltyLeaderboardSub')), findsOneWidget);
      for (final n in ['Jezdec1', 'Jan', 'Kuba', 'Petra', 'Motomilan']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('4.'), findsOneWidget);
      expect(find.text(_t('loyaltyShowMe')), findsOneWidget);
      expect(find.text(_t('loyaltyShowMeOn')), findsOneWidget);
      for (final e in ['🏆', '🥇', '🥈', '🥉', '👑']) {
        expect(find.textContaining(e), findsNothing, reason: e);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('the switch runs the same opt-in (selection click + status re-read)', (t) async {
      await stubSupabase();
      final haptics = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'HapticFeedback.vibrate') haptics.add('${c.arguments}');
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      var reads = 0;
      await pumpV2(t, page(), overrides: [
        ...leaderboardOverrides(),
        loyaltyStatusProvider.overrideWith((ref) async {
          reads++;
          return const LoyaltyStatus(
              level: 6, percent: 6, rankName: 'X', colorHex: '#000000', qualifyingCount: 11, serverNickname: 'Jan');
        }),
      ], reducedMotion: true);
      await _lb(t);
      final before = reads;
      await t.ensureVisible(find.byType(Switch));
      await t.tap(find.byType(Switch));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _lb(t);
      expect(haptics, contains('HapticFeedbackType.selectionClick'));
      expect(reads, greaterThan(before));
    });

    testWidgets('empty month: the empty text; no nickname: the nickname hint', (t) async {
      await pumpV2(t, page(), overrides: leaderboardOverrides(empty: true, nick: null), reducedMotion: true);
      await _lb(t);
      expect(find.text(_t('loyaltyLeaderboardEmpty')), findsOneWidget);
      expect(find.text(_t('loyaltyNeedNickname')), findsOneWidget);
    });

    testWidgets('flag OFF: the old section unchanged', (t) async {
      await pumpV2(t, page(), overrides: leaderboardOverrides(), v2: false);
      await _lb(t);
      expect(find.byType(LoyaltyLeaderboardV2), findsNothing);
      expect(find.text('🏆'), findsOneWidget);
      // The old look's reveal / glow loops: let them go before the end.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });
}
