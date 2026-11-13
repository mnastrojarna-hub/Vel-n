// Accepted clarity fixes, part "after" (úloha E, 2026-11-13), widget level:
// codes wait for the documents (P2-06), the day after the end is taken on
// the extend tab (E3-01), swap vs. whole-term change (E3-03), bikes hidden
// by the licence (E3-04), "Volno" instead of a tick (E3-05), the late
// pickup headline (E3-10) and the natural ride-decision question (RD-05).
// The full edit screen (E3-02 / E3-06 / E3-04 filter) is in
// e_fix_after_edit_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_hints_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_calendar_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_moto_rows_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_moto_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_notes_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_swap_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Override _docs(bool complete) => docsFabStatusProvider.overrideWith((ref) => Future.value(DocsScreenStatus(
    complete
        ? DocsVerification(idVerifiedAt: DateTime(2026, 1, 1), licenseVerifiedAt: DateTime(2026, 1, 1))
        : const DocsVerification(),
    null)));

Motorcycle _moto(String id, String model) => Motorcycle.fromJson({
      'id': id,
      'model': model,
      'brand': model.split(' ').first,
      'category': 'cestovni',
      'status': 'active',
      'branches': {'name': 'Mezná', 'type': 'obslužná'},
      'license_required': 'A2',
      'images': const <String>[],
      'price_mon': 1000,
    });

Future<void> _pump(WidgetTester t, Widget child, {String lang = 'cs', Size size = const Size(360, 1400), String? shot}) async {
  final key = GlobalKey();
  await pumpV2(t, SingleChildScrollView(child: child),
      lang: lang, size: size, reducedMotion: true, overrides: resOverrides(), boundaryKey: key);
  await _frames(t);
  // Review PNG only with MG_SHOTS_DIR set (not a golden).
  if (shot != null) await maybeShot(t, key, shot);
}

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

  group('P2-06 codes line follows the documents', () {
    for (final complete in [false, true]) {
      testWidgets('documents complete=$complete', (t) async {
        final r = resv('p6', status: 'reserved', from: 5, to: 7);
        await pumpV2(t, ResCodesWhenLineV2(res: r), overrides: [...resOverrides(), _docs(complete)], reducedMotion: true);
        await _frames(t);
        final line = find.descendant(of: find.byKey(const ValueKey('res-codes-when')), matching: find.byType(Text));
        final text = t.widget<Text>(line).data!;
        if (complete) {
          expect(text, _t('claResCodesWhen'));
        } else {
          expect(text, contains('až po nahrání dokladů'));
        }
      });
    }
  });

  group('E3-01 extend tab: the day after the end is taken', () {
    final s = DateTime(2030, 6, 10), e = DateTime(2030, 6, 13);
    Widget cal(String mode, {required bool taken, bool active = false}) => EditReservationCalendarV2View(
          year: 2030,
          month: 6,
          mode: mode,
          origStart: s,
          origEnd: e,
          newStart: s,
          newEnd: e,
          isOccupied: (d) => taken && d.day >= 14 && d.day <= 16 && d.month == 6,
          onDayTap: (_) {},
          onPrevMonth: () {},
          onNextMonth: () {},
          isActive: active,
        );
    const key = ValueKey('res-edit-extend-taken');
    for (final active in [false, true]) {
      testWidgets('taken, active=$active -> persistent note', (t) async {
        await _pump(t, cal('extend', taken: true, active: active));
        expect(find.byKey(key), findsOneWidget);
        expect(find.text(_t(active ? 'jxExtendEndTakenActive' : 'jxExtendEndTaken')), findsOneWidget);
      });
    }
    testWidgets('free day after the end -> no note', (t) async {
      await _pump(t, cal('extend', taken: false));
      expect(find.byKey(key), findsNothing);
    });
    for (final mode in ['shorten', 'move']) {
      testWidgets('$mode tab -> no note', (t) async {
        await _pump(t, cal(mode, taken: true));
        expect(find.byKey(key), findsNothing);
      });
    }
    testWidgets('German at 320 px: no overflow', (t) async {
      await _pump(t, cal('extend', taken: true, active: true), lang: 'de', size: const Size(320, 1400), shot: 'e3_01__de__320');
      expect(find.text(_t('jxExtendEndTakenActive', 'de')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('E3-03 / E3-04 / E3-05 bike lists', () {
    final yamaha = _moto('m-y', 'Yamaha PW50');
    final shotgun = _moto('m-s', 'Royal Enfield Shotgun 650');
    Widget swap({String? selected}) => SwapMotoViewV2(
          rangeText: 'Termín',
          dateText: '2.12.2026',
          onPickDate: () {},
          timePicker: const SizedBox(height: 10),
          currentMotoName: 'Husqvarna 701 SM',
          branchFilter: const SizedBox.shrink(),
          motos: AsyncValue.data([yamaha, shotgun]),
          candidates: (l) => l,
          avail: const {'m-y': true, 'm-s': false},
          availLoading: false,
          selectedId: selected,
          trailerBlocked: (_) => false,
          onTapMoto: (_, __) {},
          net: null,
          netLoading: false,
          saving: false,
          canConfirm: false,
          onConfirm: () {},
        );
    Widget change() => EditMotoChangeViewV2(
          currentMotoName: 'Husqvarna 701 SM',
          currentMoto: null,
          newMotoName: null,
          expanded: true,
          availLoading: false,
          onToggleExpanded: () {},
          branchFilter: const SizedBox.shrink(),
          motos: AsyncValue.data([yamaha]),
          available: (l) => l,
          avail: const {'m-y': true},
          selectedId: null,
          trailerBlocked: (_) => false,
          onTapMoto: (_, __) {},
        );

    testWidgets('swap tab: mid-term heading + licence note', (t) async {
      await _pump(t, swap());
      expect(find.text(_t('jxSwapMidTitle')), findsOneWidget);
      expect(find.text(_t('jxLicenceHiddenNote')), findsOneWidget);
    });
    testWidgets('whole-term change: subtitle, "VYBER", licence note', (t) async {
      await _pump(t, change());
      expect(find.text(_t('jxMotoWholeSub')), findsOneWidget);
      expect(find.text(_t('jxPickNewMoto')), findsOneWidget);
      expect(find.text(_t('selectNewMoto')), findsNothing);
      expect(find.text(_t('jxLicenceHiddenNote')), findsOneWidget);
    });
    testWidgets('free row says "Volno" (no tick); selected row has the tick', (t) async {
      await _pump(t, swap());
      expect(find.byKey(const ValueKey('edit-moto-free-pill')), findsOneWidget);
      expect(find.text(_t('jxBikeFree')), findsOneWidget);
      expect(find.text(_t('swap.occupied')), findsOneWidget);
      bool hasIcon(String n) => t.widgetList<MgIcon>(find.descendant(of: find.byType(EditMotoRowV2), matching: find.byType(MgIcon))).any((i) => i.name == n);
      expect(hasIcon(MgIcons.checkCircle), isFalse);
      expect(hasIcon(MgIcons.check), isFalse);
      await _pump(t, swap(selected: 'm-y'));
      expect(find.byKey(const ValueKey('edit-moto-free-pill')), findsNothing);
      expect(hasIcon(MgIcons.check), isTrue);
    });
    testWidgets('German at 320 px: no overflow', (t) async {
      await _pump(t, Column(children: [swap(), change()]), lang: 'de', size: const Size(320, 2400), shot: 'e3_lists__de__320');
      expect(find.text(_t('jxSwapMidTitle', 'de')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('E3-10 late pickup headline (v2 edit)', () {
    Widget hint() => const ResPickupTimeV2(picker: SizedBox(height: 52), legacyLine: false, selfServiceHint: true);
    testWidgets('headline + body instead of the long hint', (t) async {
      await _pump(t, hint());
      expect(find.text(_t('jxLateHead')), findsOneWidget);
      expect(find.text(_t('jxLateBody')), findsOneWidget);
      expect(find.text(_t('ssPickupHint')), findsNothing);
    });
    testWidgets('German at 320 px: no overflow', (t) async {
      await _pump(t, hint(), lang: 'de', size: const Size(320, 900), shot: 'e3_10__de__320');
      expect(find.text(_t('jxLateHead', 'de')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  test('RD-05 natural decision question (cs)', () {
    expect(_t('gdaRecDecide'), 'Jedeš dál, nebo jízdu ukončíš a uložíš?');
  });
}
