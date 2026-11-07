// fix:r2:areas — owner 2026-11-07 "Obecně ta aplikace měla být jenom
// upgrade vzhledu … drž se spíše původní aplikace": the v2 edit view keeps
// the old page's entry points (?tab=swap opens Výměna at once), its blocker
// and CTA on the chooser, all Rezervace filters one tap away, and the v2
// surfaces that were still the old look inside v2 (rounding note, history).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_chooser_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_view_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reservations_cases.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
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

  group('edit deep link ?tab=swap', () {
    // The full ReservationEditScreen cannot be pumped in a widget test (its
    // initState calls ref.invalidate before the element is mounted — a
    // debug-only assert of the old screen), so the seam line is guarded at
    // source level and the view behaviour at widget level.
    test('the v2 seam opens Výměna when the screen is on the swap tab', () {
      final src = File('lib/features/reservations/reservation_edit_screen.dart').readAsStringSync();
      expect(src, contains("initialIntent: _tab == 'swap' ? ResEditIntent.swap : null,"));
    });

    final b = resv('d1', status: 'reserved', from: 5, to: 7);
    Widget view(ResEditIntent? intent) => ResEditV2View(
          booking: b,
          tab: intent == ResEditIntent.swap ? 'swap' : 'extend',
          isActive: false,
          canMove: true,
          canSwap: true,
          returnTimeAvailable: false,
          calc: editCalc(b),
          sections: ResEditV2Sections(
              swap: intent == ResEditIntent.swap ? const SizedBox(key: ValueKey('swap-section'), height: 120) : null),
          stornoPct: null,
          missingSizes: const [],
          saveLabel: intent == ResEditIntent.swap ? null : _t('saveChangesBtn'),
          onSave: null,
          saving: false,
          onBack: () {},
          onSelectExtend: () {},
          onSelectShorten: () {},
          onSelectMove: () {},
          onSelectSwap: () {},
          initialIntent: intent,
        );

    testWidgets('initial swap intent: the swap section at once, no chooser tap', (t) async {
      await pumpV2(t, view(ResEditIntent.swap), overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(ResEditChooserV2), findsNothing);
      expect(find.byKey(const ValueKey('swap-section')), findsOneWidget);
      expect(find.text(_t('swap.tab')), findsWidgets);
    });

    testWidgets('no initial intent: the chooser as before', (t) async {
      await pumpV2(t, view(null), overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(ResEditChooserV2), findsOneWidget);
    });
  });

  group('edit chooser keeps the blocker and the CTA', () {
    final b = resv('e1', status: 'reserved', from: 4, to: 6);
    Widget edit({List<String> missing = const [], VoidCallback? onSave, bool saving = false}) => ResEditV2View(
          booking: b,
          tab: 'extend',
          isActive: false,
          canMove: true,
          canSwap: true,
          returnTimeAvailable: false,
          calc: editCalc(b),
          sections: const ResEditV2Sections(),
          stornoPct: null,
          missingSizes: missing,
          saveLabel: _t('saveChangesBtn'),
          onSave: onSave,
          saving: saving,
          onBack: () {},
          onSelectExtend: () {},
          onSelectShorten: () {},
          onSelectMove: () {},
          onSelectSwap: () {},
        );

    testWidgets('missing sizes: warning + disabled CTA at first glance', (t) async {
      await pumpV2(t, edit(missing: const ['Helma', 'Boty']), overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(ResEditChooserV2), findsOneWidget);
      expect(find.text(_t('fillGearSizesOnDelivery')), findsOneWidget);
      expect(find.text('${_t('missingLabel')}: Helma, Boty'), findsOneWidget);
      final cta = t.widget<MgCta>(find.byType(MgCta));
      expect(cta.enabled, isFalse);
    });

    testWidgets('a save started from the chooser keeps the busy CTA', (t) async {
      await pumpV2(t, edit(saving: true), overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 400));
      final cta = t.widget<MgCta>(find.byType(MgCta));
      expect(cta.busy, isTrue);
    });

    testWidgets('nothing to save and nothing missing: chooser without a dock (as before)', (t) async {
      await pumpV2(t, edit(), overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MgCta), findsNothing);
    });
  });
}
