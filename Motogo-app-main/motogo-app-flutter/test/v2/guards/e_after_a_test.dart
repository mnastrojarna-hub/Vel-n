// Clarity items after payment, round "e_after_a" (2026-11-13), new look only:
// G-382 a filter that hides existing bookings offers "show all" next to the
// old "Žádné rezervace" block; G-697 the theft "was it secured?" question
// says it must be answered; G-473 the restore refusal heading no longer says
// "bike taken" when the reason is something else.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/reservations/booking_restore.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_theft_view_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _cs(String key) => AppTranslations.of('cs').tr(key);
void _n() {}

Widget _theft({bool? secured, bool reported = true}) => SosTheftViewV2(
    reported: reported,
    submitting: false,
    secured: secured,
    onSecured: (_) {},
    onBack: _n,
    onCallPolice: _n,
    onReport: _n,
    onReplacement: _n,
    onNoReplacement: _n);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  group('G-382 empty filter with other bookings', () {
    testWidgets('keeps the old block and adds "show all", which switches the filter to Vše', (t) async {
      final list = [resv('a1', status: 'reserved', from: 3, to: 5)];
      await pumpV2(t, const ReservationsScreenV2(),
          size: const Size(412, 1600), overrides: resOverrides(list: list, filter: 'cancelled'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(_cs('noReservations')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('noResBookCta')), findsOneWidget);
      final link = find.byKey(const ValueKey('ea-show-all'));
      expect(link, findsOneWidget);
      expect(find.text('Ukázat všechny rezervace'), findsOneWidget);
      final container = ProviderScope.containerOf(t.element(find.byType(ReservationsScreenV2)));
      await t.tap(link);
      await t.pump(const Duration(milliseconds: 600));
      expect(container.read(resFilterProvider), 'all');
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('no link when the account has no booking or the filter is Vše', (t) async {
      await pumpV2(t, const ReservationsScreenV2(),
          size: const Size(412, 1600), overrides: resOverrides(list: const [], filter: 'cancelled'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(_cs('noReservations')), findsOneWidget);
      expect(find.byKey(const ValueKey('ea-show-all')), findsNothing);
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('German at 320 px fits', (t) async {
      final list = [resv('a1', status: 'completed', from: -9, to: -7)];
      await pumpV2(t, const ReservationsScreenV2(),
          lang: 'de', size: const Size(320, 1400), overrides: resOverrides(list: list, filter: 'aktivni'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Alle Reservierungen zeigen'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 2));
    });
  });

  group('G-697 theft: secured question', () {
    testWidgets('unanswered shows the hint; answered hides it', (t) async {
      await pumpV2(t, _theft(), size: const Size(360, 2400), scaffold: false);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(_cs('theftSelectSecured')), findsOneWidget);
      await pumpV2(t, _theft(secured: true), size: const Size(360, 2400), scaffold: false);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(_cs('theftSelectSecured')), findsNothing);
    });
  });

  group('G-473 restore refusal heading', () {
    final tr = AppTranslations.of('cs');
    test('v2: own booking / closed branch / trailer = "Nelze obnovit"', () {
      for (final r in ['own_overlap', 'branch_closed', 'trailer']) {
        expect(restoreOccupiedTitle(tr, RestoreRefused('moto_unavailable', reason: r), v2: true),
            tr.tr('cannotRestore'));
      }
    });
    test('v2: bike really taken keeps "occupied"; old look always unchanged', () {
      expect(restoreOccupiedTitle(tr, const RestoreRefused('moto_unavailable', reason: 'moto_overlap'), v2: true),
          tr.tr('motoOccupiedTitle'));
      expect(restoreOccupiedTitle(tr, const RestoreRefused('moto_unavailable'), v2: true),
          tr.tr('motoOccupiedTitle'));
      for (final r in ['own_overlap', 'branch_closed', 'trailer', 'moto_overlap']) {
        expect(restoreOccupiedTitle(tr, RestoreRefused('moto_unavailable', reason: r), v2: false),
            tr.tr('motoOccupiedTitle'));
      }
    });
  });
}
