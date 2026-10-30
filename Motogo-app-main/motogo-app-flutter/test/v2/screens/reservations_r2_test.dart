// fix:reservations r2 — the list's ONE dark rank strip (V22 R5.2: the card
// that needs action; white strip with btnGhostLight + btnText on the
// others, same callbacks), the timeline event row (never overflows, the
// date moves under the label whatever its width), the edit time dropdown
// in the app font, and „Znovu rezervovat" keeping the catalog dates in v2
// (owner 2026-10-22 „nic nevyplňovat dvakrát“; old look unchanged).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/reservations/res_actions.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_card_actions_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_sections_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_fit_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';
import 'reservations_cases.dart';

DateTime _fresh() => DateTime.now().subtract(const Duration(minutes: 5));

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

  group('one dark strip per list', () {
    final far = resv('f1', status: 'reserved', from: 20, to: 22);
    final near = resv('n1', status: 'reserved', from: 3, to: 5);
    final active = resv('a1', status: 'active', from: -1, to: 1, handedOver: rday(-1));
    final done = resv('d1', status: 'completed', from: -12, to: -10, rating: 5);
    final unpaid = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11, created: _fresh());

    test('unpaid / verifying > running > nearest upcoming > the first card', () {
      final pending = PendingBooking(id: unpaid.id, totalPrice: 1, createdAt: _fresh());
      expect(resPrimaryCardId([far, active, unpaid, done], pending), unpaid.id);
      expect(resPrimaryCardId([far, near, active, done], null), active.id);
      expect(resPrimaryCardId([far, near, done], null), near.id);
      expect(resPrimaryCardId([done, resv('x1', status: 'cancelled', from: 20, to: 22)], null), done.id);
      expect(resPrimaryCardId(const [], null), isNull);
    });

    for (final c in [('all', 'a1'), ('unpaid', 'u1')]) {
      testWidgets('list ${c.$1}: the rank CTA only on ${c.$2}', (tester) async {
        await pumpV2(tester, const ReservationsScreenV2(), size: const Size(412, 4000), overrides: listCases()[c.$1]!());
        await tester.pump(const Duration(seconds: 1));
        final withCta = find.ancestor(of: find.byType(MgCta), matching: find.byType(ReservationCardV2));
        expect(withCta, findsOneWidget);
        expect(tester.widget<ReservationCardV2>(withCta).reservation.id, startsWith(c.$2));
        expect(find.byType(ReservationCardV2).evaluate().length, greaterThan(1));
        expect(find.byType(MgBtnGhostLight), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      });
    }
  });

  group('card strip', () {
    Future<AppTranslations> pump(WidgetTester tester, Reservation r, bool primary,
        {VoidCallback? onTap, VoidCallback? onEdit, VoidCallback? onRestore}) async {
      await pumpV2(
          tester,
          SingleChildScrollView(
            child: ReservationCardV2(
                reservation: r, primary: primary, onTap: onTap ?? () {}, onEdit: onEdit, onRestore: onRestore),
          ));
      await tester.pump(const Duration(milliseconds: 300));
      return t(tester.element(find.byType(ReservationCardV2)));
    }

    testWidgets('primary: rank CTA + glass ghost (as before)', (tester) async {
      await pump(tester, resv('n1', status: 'reserved', from: 3, to: 5), true, onEdit: () {});
      expect(find.byType(MgCta), findsOneWidget);
      expect(find.byType(MgBtnGhostDark), findsOneWidget);
      expect(find.byType(MgBtnGhostLight), findsNothing);
    });

    testWidgets('other card: btnGhostLight Detail + btnText Upravit, same callbacks', (tester) async {
      var opened = 0, edited = 0;
      final tr = await pump(tester, resv('n1', status: 'reserved', from: 3, to: 5), false,
          onTap: () => opened++, onEdit: () => edited++);
      expect(find.byType(MgCta), findsNothing);
      expect(find.byType(MgBtnGhostDark), findsNothing);
      await tester.tap(find.widgetWithText(MgBtnGhostLight, tr.detail));
      await tester.tap(find.widgetWithText(MgBtnText, tr.edit));
      expect((opened, edited), (1, 1));
    });

    testWidgets('other card: Obnovit = restore, Hodnotit = detail, SOS stays', (tester) async {
      var restored = 0, opened = 0;
      var tr = await pump(tester, resv('c1', status: 'cancelled', from: 20, to: 22), false,
          onTap: () => opened++, onRestore: () => restored++);
      await tester.tap(find.text(tr.tr('restoreBtn')));
      expect((restored, opened), (1, 0));
      tr = await pump(tester, resv('d1', status: 'completed', from: -12, to: -10), false, onTap: () => opened++);
      await tester.tap(find.text(tr.tr('rateBtn')));
      expect(opened, 1);
      await pump(tester, resv('s1', status: 'active', from: -1, to: 2, handedOver: rday(-1)), false, onEdit: () {});
      expect(find.text('SOS'), findsOneWidget);
    });
  });

  group('timeline event row', () {
    const label = Text('Zurückgegeben', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700));
    const date = Text('28.12.2026 23:58', style: TextStyle(fontSize: 10));
    Widget row(double w) => Center(
        child: SizedBox(width: w, child: Builder(builder: (c) => resV2EventRow(c, label, date) ?? const Text('v1'))));

    testWidgets('v2: one row when it fits, date under the label when not', (tester) async {
      for (final w in [400.0, 150.0, 90.0]) {
        await pumpV2(tester, row(w));
        expect(tester.takeException(), isNull, reason: 'width $w');
        final dy = tester.getTopLeft(find.text(date.data!)).dy - tester.getTopLeft(find.text(label.data!)).dy;
        if (w == 400) expect(dy.abs(), lessThan(4));
        if (w == 90) expect(dy, greaterThan(8));
      }
    });

    testWidgets('old look keeps its own row', (tester) async {
      await pumpV2(tester, row(300), v2: false);
      expect(find.text('v1'), findsOneWidget);
    });
  });

  testWidgets('edit time dropdown: digits in the app font, not the platform one', (tester) async {
    await pumpV2(tester, EditTimePickerV2(label: 'Čas', hour: '09', minute: '00', onHour: (_) {}, onMinute: (_) {}));
    final f = find.byType(DropdownButton<String>).first;
    final family = DefaultTextStyle.of(tester.element(f)).style.fontFamily;
    expect(family, isNotNull);
    expect(tester.widget<DropdownButton<String>>(f).style?.fontFamily, family);
  });

  group('Znovu rezervovat', () {
    final res = resv('d1', status: 'completed', from: -12, to: -10, rating: 5);
    final s = rday(5), e = rday(7);

    Future<ProviderContainer> run(WidgetTester tester, {required bool v2, DateTime? start}) async {
      final c = ProviderContainer(overrides: [
        catalogFilterProvider.overrideWith((ref) => CatalogFilter(category: 'naked', startDate: start ?? s, endDate: e)),
      ]);
      addTearDown(c.dispose);
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
                body: Consumer(builder: (ctx, ref, _) => TextButton(onPressed: () => rebookSameMoto(ctx, ref, res), child: const Text('go'))))),
        GoRoute(path: '/moto/:id', builder: (_, st) => Scaffold(body: Text('moto ${st.pathParameters['id']}'))),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('cs'),
          supportedLocales: supportedLocales,
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          builder: (_, child) => MgV2Scope(enabled: v2, child: child!),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('moto ${res.motoId}'), findsOneWidget);
      return c;
    }

    String toast(WidgetTester tester) => t(tester.element(find.byType(Scaffold).last)).tr('selectDateSameMoto');

    testWidgets('v2: the catalog keeps the trip dates, no "Vyber termín"', (tester) async {
      final c = await run(tester, v2: true);
      final f = c.read(catalogFilterProvider);
      expect((f.startDate, f.endDate, f.category), (s, e, 'naked'));
      expect(find.text(toast(tester)), findsNothing);
    });

    testWidgets('v2 without usable dates (past start): asks for dates', (tester) async {
      await run(tester, v2: true, start: rday(-2));
      expect(find.text(toast(tester)), findsOneWidget);
    });

    testWidgets('old look: clean catalog + "Vyber termín" (unchanged)', (tester) async {
      final c = await run(tester, v2: false);
      final f = c.read(catalogFilterProvider);
      expect((f.startDate, f.endDate, f.category), (null, null, null));
      expect(find.text(toast(tester)), findsOneWidget);
    });
  });
}
