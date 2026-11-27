// 5.0.3 (owner 2026-11-27: "když otevřu Rezervace … musí tam být výrazné
// tlačítko Nová rezervace … hodí mě do Motorek, kde bude třeba Vyber si
// motorku"): the v2 Rezervace tab has ONE booking button in every state,
// right under the header; it opens Motorky the way every jump with context
// does ("‹ Rezervace" chip) and the Motorky header says "Vyber si motorku"
// until a tab switch.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/shell/mg_origin_chip.dart';
import 'package:motogo_app/core/v2/shell/shell_nav_map.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/v2/motorky_header_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_filter_tabs_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_list_header_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reservations_cases.dart' show listCases;
import '../support/bars_harness.dart';
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

final _btn = find.byKey(const ValueKey('res-new-booking'));

final _shell = <String, Widget Function(GoRouterState)>{
  '/reservations': (_) => const ReservationsScreenV2(),
  '/search': (_) => const MotorkyScreenV2(),
  '/profile': (_) => const Scaffold(body: Text('route:/profile')),
};

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  for (final e in listCases().entries) {
    testWidgets('"Nová rezervace" is there in state "${e.key}" — once, full width, between the header and the filter',
        (t) async {
      await pumpV2(t, const ReservationsScreenV2(), overrides: e.value(), reducedMotion: true);
      await t.pump(const Duration(milliseconds: 600));
      expect(_btn, findsOneWidget);
      final b = t.widget<MgBtnInk>(_btn);
      expect(b.label, 'Nová rezervace');
      expect(b.onTap, isNotNull);
      final r = t.getRect(_btn);
      expect(r.left, 16);
      expect(r.right, 360 - 16);
      expect(r.top, greaterThanOrEqualTo(t.getRect(find.byType(ResListHeaderV2)).bottom));
      expect(r.bottom, lessThanOrEqualTo(t.getRect(find.byType(ResFilterTabsV2)).top));
      // One booking button: the empty block no longer carries its own.
      expect(find.byWidgetPredicate((w) => w is MgCta && w.label == 'Rezervovat motorku'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 2));
      await _drain(t);
    });
  }

  for (final size in const [Size(320, 640), Size(360, 780)]) {
    testWidgets('${size.width.toInt()}×${size.height.toInt()}: the button does not push the first booking off the screen',
        (t) async {
      final list = [resv('a2', status: 'reserved', from: 6, to: 8, self: false, bike: 'BMW R 1200 GS Adventure')];
      for (final lang in kV2Langs) {
        await pumpV2(t, const ReservationsScreenV2(),
            overrides: resOverrides(list: list), size: size, lang: lang, reducedMotion: true);
        await t.pump(const Duration(milliseconds: 600));
        expect(t.takeException(), isNull, reason: lang);
        final b = t.getRect(_btn);
        expect(b.height, size.height < 700 ? 44 : 52, reason: 'compact on a short phone');
        final card = t.getRect(find.byType(ReservationCardV2).first);
        // The card's head (status, bike, number: its first 160 px) stays on
        // the first screen, above the 64 px menu.
        expect(card.top + 160, lessThanOrEqualTo(size.height - 64), reason: '$lang card top ${card.top}');
        expect(card.top, greaterThan(b.bottom));
        await t.pump(const Duration(seconds: 2));
      }
      await _drain(t);
    });
  }

  testWidgets('tap → Motorky: "‹ Rezervace" chip + "Vyber si motorku" under the title; gone after a tab switch',
      (t) async {
    final router = await pumpBarsShell(t, '/reservations', _shell,
        overrides: resOverrides(list: sampleList()), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(_btn);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(_path(router), '/search');
    expect(find.byType(MotorkyScreenV2), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2)));
    final origin = c.read(v2TabOriginProvider);
    expect(origin?.tab, 1);
    expect(origin?.route, '/reservations');
    expect(origin?.hintKey, 'resNewBookingHint');
    final header = find.byType(MotorkyHeaderV2);
    final hint = find.descendant(of: header, matching: find.text('Vyber si motorku'));
    expect(hint, findsOneWidget);
    expect(find.byKey(const ValueKey('mg-origin-hint')), findsOneWidget);
    // Under the title, inside the header, never over the mode switch.
    final title = t.getRect(find.descendant(of: header, matching: find.text('Motorky')));
    expect(t.getRect(hint).top, greaterThanOrEqualTo(title.bottom));
    expect(t.getRect(hint).bottom, lessThan(t.getRect(header).bottom));
    // The chip goes back where the jump came from.
    final chip = find.descendant(of: find.byType(MgOriginChip), matching: find.text('Rezervace'));
    expect(chip, findsOneWidget);
    await t.tap(chip);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(_path(router), '/reservations');
    // Again, then a real tab switch ends the jump: no hint on a later visit.
    await t.tap(_btn);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Vyber si motorku'), findsOneWidget);
    router.go('/profile');
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(c.read(v2TabOriginProvider), isNull);
    router.go('/search');
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(MotorkyHeaderV2), findsOneWidget);
    expect(find.text('Vyber si motorku'), findsNothing);
    expect(t.takeException(), isNull);
    await _drain(t);
  });

  testWidgets('Motorky opened on its own has no hint; the hint line fits 320 px in 8 languages', (t) async {
    for (final lang in kV2Langs) {
      final router = await pumpBarsShell(t, '/reservations', _shell,
          overrides: resOverrides(), reducedMotion: true, size: const Size(320, 640), top: 24, bottom: 0, lang: lang);
      await t.pump(const Duration(milliseconds: 600));
      router.go('/search');
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('mg-origin-hint')), findsNothing, reason: lang);
      router.go('/reservations');
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(_btn);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      final hint = find.byKey(const ValueKey('mg-origin-hint'));
      expect(hint, findsOneWidget, reason: lang);
      expect(t.getRect(hint).right, lessThanOrEqualTo(320 - 16), reason: lang);
      expect(t.takeException(), isNull, reason: lang);
      await _drain(t);
    }
  });
}
