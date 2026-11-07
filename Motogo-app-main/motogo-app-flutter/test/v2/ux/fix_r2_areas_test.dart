// fix:r2:areas — owner 2026-11-07 "Obecně ta aplikace měla být jenom
// upgrade vzhledu … drž se spíše původní aplikace": the v2 edit view keeps
// the old page's entry points (?tab=swap opens Výměna at once), its blocker
// and CTA on the chooser, all Rezervace filters one tap away (old Wrap),
// and the card-minimum note of the edit price in the v2 look.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_chooser_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show DayPrices;
import 'package:motogo_app/features/payment/v2/pay_parts_v2.dart' show PayRoundingNoteV2;
import 'package:motogo_app/features/payment/widgets/card_rounding_note.dart';
import 'package:motogo_app/features/reservations/reservation_edit_price_calc.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_price_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_filter_tabs_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reservations_cases.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;


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

  group('Rezervace filters: all 5 one tap away (old Wrap of chips)', () {
    for (final lang in ['cs', 'de', 'fr', 'uk']) {
      for (final w in [320.0, 360.0]) {
        testWidgets('$lang ${w.toInt()} dp: every filter hit-testable without scrolling', (t) async {
          await pumpV2(t, const ReservationsScreenV2(),
              lang: lang, size: Size(w, 780), overrides: resOverrides(list: sampleList()), reducedMotion: true);
          await t.pump(const Duration(milliseconds: 800));
          expect(t.takeException(), isNull);
          final tabs = find.byType(ResFilterTabsV2);
          for (final k in kResFilterI18n) {
            final f = find.descendant(of: tabs, matching: find.text(_t(k, lang)));
            expect(f.hitTestable(), findsOneWidget, reason: '$lang $k');
            final r = t.getRect(f);
            expect(r.left, greaterThanOrEqualTo(0), reason: '$lang $k');
            expect(r.right, lessThanOrEqualTo(w), reason: '$lang $k');
          }
          await t.tap(find.descendant(of: tabs, matching: find.text(_t('cancelled', lang))));
          await t.pump(const Duration(milliseconds: 600));
          final c = ProviderScope.containerOf(t.element(find.byType(ReservationsScreenV2)));
          expect(c.read(resFilterProvider), 'cancelled');
        });
      }
    }

    testWidgets('wrapped tabs: mid-swipe exactly one light label, selection follows', (t) async {
      final p = ValueNotifier<double>(0);
      await pumpV2(
          t,
          ResFilterTabsV2(
              value: 'all',
              counts: const {'all': 4, 'aktivni': 1, 'nadchazejici': 1, 'dokoncene': 1, 'cancelled': 1},
              onSelect: (_) {},
              onStep: (_) {},
              dragProgress: p),
          size: const Size(320, 780),
          reducedMotion: true);
      await t.pump();
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byKey(const ValueKey('res-filter-thumb')), findsNothing);
      List<AnimatedDefaultTextStyle> light() => t
          .widgetList<AnimatedDefaultTextStyle>(
              find.descendant(of: find.byType(ResFilterTabsV2), matching: find.byType(AnimatedDefaultTextStyle)))
          .where((w) => w.style.color == MgColors.onDark)
          .toList();
      expect(light().length, 1);
      p.value = 0.6;
      await t.pump();
      expect(light().length, 1);
      p.value = 0;
      await t.pump();
      expect(light().length, 1);
    });
  });

  group('edit price: card-minimum note in the v2 look', () {
    final b = resv('p1', status: 'reserved', from: 4, to: 6);
    EditPriceCalc calcWith(double fee) => EditPriceCalc(
          booking: b,
          newStart: b.startDate,
          newEnd: b.endDate,
          motoPrices: const DayPrices(mon: 3543, tue: 3543, wed: 3543, thu: 3543, fri: 4620, sat: 4997, sun: 4997),
          newMotoId: null,
          pickupDelivFee: fee,
          returnDelivFee: 0,
          selectedExtras: const {},
          pickupMethod: 'delivery',
          returnMethod: 'store',
          pickupTime: '12:00',
          returnTime: '23:59',
        );
    // Delivery fee chosen so that the change costs 7,50 Kč (card minimum).
    final calc = calcWith(7.5 - calcWith(0).effectivePriceDiff);

    testWidgets('a 1–15 Kč surcharge shows the v2 note (same text), not the old amber box', (t) async {
      expect(calc.effectivePriceDiff, greaterThan(1));
      expect(calc.effectivePriceDiff, lessThan(15));
      await pumpV2(t, SingleChildScrollView(child: ResEditPriceV2(booking: b, calc: calc)), overrides: resOverrides());
      expect(find.byType(PayRoundingNoteV2), findsOneWidget);
      expect(find.byType(CardRoundingNote), findsNothing);
      expect(find.textContaining('15'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  });
}
