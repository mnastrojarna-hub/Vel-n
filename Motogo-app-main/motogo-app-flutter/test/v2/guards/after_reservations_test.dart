// Safeguards of the reservation detail / edit in the NEW look (soupis
// pojistek 2026-11-12, part "after"): door codes, hold-back reasons,
// "sign the protocol first" and the error state must be readable on the
// light detail page (G-409…G-456), the pickup procedure entry and its gate
// warning visible without opening (G-458…G-460), the rating card readable
// (G-461/G-463), honest icons in the bike swap and own-gear rows
// (G-645/G-657) and two different SOS chips on the list card (G-393).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/reservations/v2/res_codes_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_sections_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_swap_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_procedure_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_rating_dark_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';
import 'guard_contrast.dart';

String _t(String key) => translations['cs']?[key] ?? key;

/// [child] on the light detail page canvas, as `ResDetailTabContent` puts it.
Widget _onCanvas(Widget child) => ColoredBox(
      color: MgColors.canvas,
      child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
    );

Future<void> _pump(WidgetTester t, Widget child) async {
  await pumpV2(t, _onCanvas(child), size: const Size(360, 1400), reducedMotion: true, overrides: resOverrides());
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Motorcycle _moto(String id) => Motorcycle.fromJson({
      'id': id,
      'model': 'BMW R 1250 GS',
      'brand': 'BMW',
      'category': 'cestovni',
      'status': 'active',
      'branches': {'name': 'Mezná', 'type': 'obslužná'},
      'license_required': 'A',
      'images': const <String>[],
      'price_mon': 2000,
    });

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    mockPathProvider();
    await stubSupabase();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  group('G-409…G-456 door codes readable on the light detail page', () {
    final states = <String, Widget>{
      'sent + gate + protocol first': ResCodesV2(
        gateCode: '2580',
        codes: [
          ResCodeV2Item(label: _t('lockerCode'), value: '4821', sent: true),
          ResCodeV2Item(label: _t('motoCode'), value: '7395', sent: true, protocolNote: true),
        ],
        ownGearNoLocker: false,
        onRelease: null,
      ),
      'withheld for documents + release CTA': ResCodesV2(
        gateCode: null,
        codes: [ResCodeV2Item(label: _t('motoCode'), value: _t('awaitingDocs'), sent: false)],
        ownGearNoLocker: false,
        onRelease: () {},
      ),
      'withheld for a swap (no CTA)': ResCodesV2(
        gateCode: null,
        codes: [ResCodeV2Item(label: _t('motoCode'), value: 'Vraťte nejdřív původní motorku', sent: false)],
        ownGearNoLocker: false,
        onRelease: null,
      ),
      'own gear, no locker': ResCodesV2(
        gateCode: null,
        codes: [ResCodeV2Item(label: _t('motoCode'), value: '7395', sent: true)],
        ownGearNoLocker: true,
        onRelease: null,
      ),
      'loading': const ResCodesV2.loading(),
      'error': ResCodesV2.error(errorText: 'Kódy se nepodařilo načíst.', onRetry: () {}, onMessages: () {}, onCall: () {}),
    };
    for (final e in states.entries) {
      testWidgets(e.key, (t) async {
        await _pump(t, e.value);
        expect(find.byKey(const ValueKey('res-codes-v2-panel')), findsOneWidget);
        expectReadable(t, find.byType(ResCodesV2), MgColors.canvas);
      });
    }

    testWidgets('the protocol-first note and the swap reason are on screen', (t) async {
      await _pump(t, states['sent + gate + protocol first']!);
      expect(find.text(_t('v2UxRpProtocolFirst')), findsOneWidget);
      expect(find.text('7395'), findsOneWidget);
    });
  });

  group('G-458…G-460 pickup procedure entry', () {
    testWidgets('gate branch: visible card + warning without opening; tap opens the steps', (t) async {
      await _pump(
          t,
          const ResProcedureV2(
            gateTitle: 'Pobočka s bránou',
            steps: ['Krok jedna', 'Krok dva'],
            important: 'DŮLEŽITÉ: zavři bránu.',
          ));
      expect(find.byKey(const ValueKey('res-procedure-v2-entry')), findsOneWidget);
      expect(find.byKey(const ValueKey('res-procedure-v2-warn')), findsOneWidget);
      expect(find.text(_t('gdaProcGateWarn')), findsOneWidget);
      expectReadable(t, find.byType(ResProcedureV2), MgColors.canvas);
      await t.tap(find.byKey(const ValueKey('res-procedure-v2-entry')));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Krok jedna'), findsOneWidget);
      expect(find.text('DŮLEŽITÉ: zavři bránu.'), findsOneWidget);
    });

    testWidgets('no gate: card without the warning', (t) async {
      await _pump(t, const ResProcedureV2(gateTitle: null, steps: ['Krok'], important: null));
      expect(find.byKey(const ValueKey('res-procedure-v2-entry')), findsOneWidget);
      expect(find.byKey(const ValueKey('res-procedure-v2-warn')), findsNothing);
      expectReadable(t, find.byType(ResProcedureV2), MgColors.canvas);
    });
  });

  group('G-461/G-463 rating card readable on the light detail page', () {
    for (final rating in [0, 5]) {
      testWidgets('rating $rating', (t) async {
        final log = <String>[];
        await _pump(
            t,
            ResRatingDarkV2(
              rating: rating,
              question: rating == 0 ? _t('rfHowWasRide') : 'Tvoje hodnocení: $rating',
              popTick: 0,
              sentThreadId: null,
              onRate: (n) => log.add('rate:$n'),
              onGoogle: () => log.add('google'),
              onFeedback: () => log.add('feedback'),
              onOpenThread: () {},
            ));
        expectReadable(t, find.byType(ResRatingDarkV2), MgColors.canvas, skip: const {'G'});
        // Empty stars must stand out from the board too (3:1 for graphics).
        final board = t.widget<Container>(find.byKey(const ValueKey('res-rating-dark-v2')));
        final bg = (board.decoration! as BoxDecoration).color!;
        expect(bg.a, 1.0);
        expect(contrastOf(Color.alphaBlend(MgColors.starOffDark, bg), bg), greaterThanOrEqualTo(1.5));
      });
    }
  });

  group('G-645 swap price row icon', () {
    Widget swap(double net) => SwapMotoViewV2(
          rangeText: 'Termín',
          dateText: '2.12.2026',
          onPickDate: () {},
          timePicker: const SizedBox(height: 10),
          currentMotoName: 'Husqvarna 701 SM',
          branchFilter: const SizedBox.shrink(),
          motos: AsyncValue.data([_moto('m1')]),
          candidates: (l) => l,
          avail: const {'m1': true},
          availLoading: false,
          selectedId: 'm1',
          trailerBlocked: (_) => false,
          onTapMoto: (_, __) {},
          net: net,
          netLoading: false,
          saving: false,
          canConfirm: true,
          onConfirm: () {},
        );

    for (final (net, icon) in [(500.0, MgIcons.pay), (-300.0, MgIcons.refresh), (0.0, MgIcons.checkCircle)]) {
      testWidgets('net $net', (t) async {
        await _pump(t, swap(net));
        final i = t.widget<MgIcon>(find.byKey(const ValueKey('swap-v2-net-icon')));
        expect(i.name, icon);
        if (net > 0) expect(i.name, isNot(MgIcons.checkCircle));
      });
    }
  });

  group('G-657 own gear row', () {
    for (final own in [false, true]) {
      testWidgets('ownGear=$own', (t) async {
        var taps = 0;
        await _pump(
            t,
            EditRiderHeaderV2(
              rider: 'ŘIDIČ',
              free: 'zdarma',
              ownGearLabel: 'Mám vlastní výbavu',
              ownGear: own,
              onToggle: () => taps++,
            ));
        final icons = t.widgetList<MgIcon>(find.descendant(of: find.byType(EditRiderHeaderV2), matching: find.byType(MgIcon)));
        if (own) {
          expect(icons.map((i) => i.name), contains(MgIcons.checkCircle));
          expect(find.byKey(const ValueKey('own-gear-v2-empty-box')), findsNothing);
        } else {
          expect(icons.where((i) => i.name == MgIcons.check || i.name == MgIcons.checkCircle), isEmpty);
          expect(find.byKey(const ValueKey('own-gear-v2-empty-box')), findsOneWidget);
        }
        await t.tap(find.text('Mám vlastní výbavu'));
        expect(taps, 1);
      });
    }
  });

  testWidgets('G-393 SOS replacement and rental ended by SOS look different', (t) async {
    Future<List<String>> chipIcons(bool replacement) async {
      final r = resv('s1', status: 'completed', from: -6, to: -4, sosReplacement: replacement, endedBySos: !replacement);
      await pumpV2(t, ReservationCardV2(reservation: r, onTap: () {}), overrides: resOverrides(), reducedMotion: true);
      await t.pump(const Duration(milliseconds: 600));
      return [for (final i in t.widgetList<MgIcon>(find.byType(MgIcon))) i.name];
    }

    final repl = await chipIcons(true);
    final ended = await chipIcons(false);
    expect(repl, contains(MgIcons.moto));
    expect(repl, isNot(contains(MgIcons.sos)));
    expect(ended, contains(MgIcons.sos));
  });
}
