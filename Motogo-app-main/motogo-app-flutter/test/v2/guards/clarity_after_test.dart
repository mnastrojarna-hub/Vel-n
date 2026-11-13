// Clarity of the reservation list / detail / edit in the NEW look (soupis
// pojistek 2026-11-12, part "after", clarity fixes): an unpaid booking is
// amber, not "all fine" green (AFT-02); documents hold the codes back —
// said before the term with the way to upload (AFT-03b); when the codes
// appear (AFT-04); the refund on the shorten dock (AFT-05); an open
// surcharge as a banner (G-424); "no bike to swap to" as a state (G-643).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_hints_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_swap_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_payment_details_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_status_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:motogo_app/features/reservations/widgets/res_payment_details_tab.dart' show PaymentDetails;
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reservations_cases.dart' show editView;
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';

String _t(String key) => translations['cs']?[key] ?? key;

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

PendingBooking _pending(Reservation r) => PendingBooking(id: r.id, totalPrice: r.totalPrice, createdAt: DateTime.now());

Override _docs(bool? complete) => docsFabStatusProvider.overrideWith((ref) => complete == null
    ? Completer<DocsScreenStatus>().future
    : Future.value(DocsScreenStatus(
        complete
            ? DocsVerification(idVerifiedAt: DateTime(2026, 1, 1), licenseVerifiedAt: DateTime(2026, 1, 1))
            : const DocsVerification(),
        null)));

Widget _detail(Reservation r) => ResDetailV2View(
      res: r,
      doorCodesAsync: const AsyncData([]),
      branchFullAddress: 'Boudky, Velké Němčice',
      onStaleRetry: null,
      onBack: () {},
      onShowCancelDialog: () {},
      onOpenFinalInvoice: (_, __) async {},
      onOpenContract: (_, __) async {},
      onRestoreBooking: (_, __) async {},
    );

/// Scrolls the lazy detail until [f] is built.
Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 250,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
  await t.pump(const Duration(milliseconds: 300));
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

  group('AFT-02 unpaid is amber, not "all fine" green', () {
    testWidgets('list card: amber status pill + filled "Nezaplaceno" chip', (t) async {
      final r = resv('p1', status: 'pending', pay: 'unpaid', from: 9, to: 11);
      await pumpV2(t, ReservationCardV2(reservation: r, onTap: () {}, payFlag: ResPayFlag.unpaid),
          overrides: resOverrides(pending: _pending(r)), reducedMotion: true);
      await _frames(t);
      expect(find.byKey(const ValueKey('res-status-pill-warn')), findsOneWidget);
      expect(find.byKey(const ValueKey('res-unpaid-chip')), findsOneWidget);
      expect(find.text(_t('payStatusUnpaid')), findsOneWidget);
      final pill = t.widget<Container>(find.byKey(const ValueKey('res-status-pill-warn')));
      expect((pill.decoration! as BoxDecoration).color, MgColors.warnDark);
    });

    testWidgets('list card: paid booking keeps its status colour, no chip', (t) async {
      final r = resv('p2', status: 'reserved', from: 9, to: 11);
      await pumpV2(t, ReservationCardV2(reservation: r, onTap: () {}), overrides: resOverrides(), reducedMotion: true);
      await _frames(t);
      expect(find.byKey(const ValueKey('res-status-pill-warn')), findsNothing);
      expect(find.byKey(const ValueKey('res-unpaid-chip')), findsNothing);
    });

    testWidgets('detail: amber hero badge, translated payment row, no raw UNPAID', (t) async {
      final r = resv('p3', status: 'pending', pay: 'unpaid', from: 9, to: 11, self: false);
      await pumpV2(t, _detail(r), overrides: [...resOverrides(pending: _pending(r)), _docs(true)], reducedMotion: true);
      await _frames(t);
      expect(find.byKey(const ValueKey('res-unpaid-chip')), findsOneWidget);
      // Hero badge + (P2-04) the detail card's own status pill, both amber.
      expect(find.byKey(const ValueKey('res-status-pill-warn')), findsWidgets);
      await _scrollTo(t, find.byKey(const ValueKey('res-pay-row-unpaid')));
      expect(find.byKey(const ValueKey('res-pay-row-unpaid')), findsOneWidget);
      expect(find.text('UNPAID'), findsNothing);
    });

    testWidgets('detail: paid row = icon + "Zaplaceno", no ✓ glyph', (t) async {
      final r = resv('p4', status: 'reserved', from: 9, to: 11, self: false);
      await pumpV2(t, _detail(r), overrides: [...resOverrides(), _docs(true)], reducedMotion: true);
      await _frames(t);
      await _scrollTo(t, find.byKey(const ValueKey('res-pay-row-paid')));
      expect(find.text(_t('paid')), findsWidgets);
      expect(find.textContaining('✓'), findsNothing);
      expect(find.byKey(const ValueKey('res-unpaid-chip')), findsNothing);
    });

    test('old look keeps its payment row unchanged', () {
      final src = File('lib/features/reservations/widgets/res_detail_tab_content.dart').readAsStringSync();
      expect(src, contains("value: res.paymentStatus == 'paid' ? '✓ \${t(context).tr('paid')}' : res.paymentStatus.toUpperCase(),"));
      expect(src, contains('if (MgV2.on(context))\n              // v2: přeložený stav'));
    });
  });

  group('AFT-03b / AFT-04 codes before the term (self-service)', () {
    testWidgets('incomplete documents: banner + button to the documents screen', (t) async {
      final r = resv('c1', status: 'reserved', from: 5, to: 7);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => Scaffold(body: ResDocsCodesBannerV2(res: r))),
        GoRoute(path: Routes.docs, builder: (_, __) => const Scaffold(body: Text('DOCS-SCREEN'))),
      ]);
      await t.pumpWidget(ProviderScope(
        overrides: [_docs(false)],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('cs'),
          supportedLocales: const [Locale('cs')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (c, w) => MgV2Scope(enabled: true, child: w!),
        ),
      ));
      await _frames(t);
      expect(find.byKey(const ValueKey('res-docs-codes-banner')), findsOneWidget);
      expect(find.text(_t('claResDocsCodesHeld')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('res-docs-codes-btn')));
      await _frames(t);
      expect(find.text('DOCS-SCREEN'), findsOneWidget);
    });

    testWidgets('in the detail: banner and "codes on pickup day" line', (t) async {
      final r = resv('c2', status: 'reserved', from: 5, to: 7);
      await pumpV2(t, _detail(r), overrides: [...resOverrides(), _docs(false)], reducedMotion: true);
      await _frames(t);
      await _scrollTo(t, find.byKey(const ValueKey('res-docs-codes-banner')));
      expect(find.byKey(const ValueKey('res-docs-codes-banner')), findsOneWidget);
      await _scrollTo(t, find.byKey(const ValueKey('res-codes-when')));
      expect(find.text(_t('claResCodesWhen')), findsOneWidget);
    });

    for (final (name, r, docs) in [
      ('complete documents', resv('c3', status: 'reserved', from: 5, to: 7), true),
      ('staffed branch', resv('c4', status: 'reserved', from: 5, to: 7, self: false), false),
    ]) {
      testWidgets('no banner: $name', (t) async {
        await pumpV2(t, _detail(r), overrides: [...resOverrides(), _docs(docs)], reducedMotion: true);
        await _frames(t);
        await _scrollTo(t, find.text(_t('financialSummary')));
        expect(find.byKey(const ValueKey('res-docs-codes-banner')), findsNothing);
      });
    }

    testWidgets('active booking (in the term): no "codes on pickup day" line', (t) async {
      final r = resv('c5', status: 'active', from: -1, to: 1, handedOver: rday(-1));
      expect(resBeforeTermSelfService(r), isFalse);
      await pumpV2(t, _detail(r), overrides: [...resOverrides(), _docs(false)], reducedMotion: true);
      await _frames(t);
      await _scrollTo(t, find.text(_t('financialSummary')));
      expect(find.byKey(const ValueKey('res-codes-when')), findsNothing);
      expect(find.byKey(const ValueKey('res-docs-codes-banner')), findsNothing);
    });

    test('upcoming self-service outside the term counts, staffed / delivery do not', () {
      expect(resBeforeTermSelfService(resv('x1', status: 'reserved', from: 5, to: 7)), isTrue);
      expect(resBeforeTermSelfService(resv('x2', status: 'reserved', from: 5, to: 7, self: false)), isFalse);
      expect(resBeforeTermSelfService(resv('x3', status: 'reserved', from: 5, to: 7, delivery: true)), isFalse);
      expect(resBeforeTermSelfService(resv('x4', status: 'cancelled', from: 5, to: 7)), isFalse);
    });
  });

  group('AFT-05 shorten: the refund on the dock', () {
    testWidgets('dock context says how much comes back', (t) async {
      final b = resv('e1', status: 'reserved', from: 4, to: 6);
      await pumpV2(t, editView(b, tab: 'shorten', addDays: -1, stornoPct: 50), overrides: resOverrides(), reducedMotion: true);
      await _frames(t);
      final ctx = t.widget<Text>(find.byKey(const ValueKey('res-edit-pay-diff')));
      expect(ctx.data, startsWith('Vrátíme ti '));
      expect(ctx.data, matches(RegExp(r'^Vrátíme ti 2\s658\sKč \(50 %\)$')));
      expect(ctx.data, isNot(contains('−')));
    });

    test('the screen seam uses the same values as the refund message', () {
      final src = File('lib/features/reservations/reservation_edit_screen.dart').readAsStringSync();
      expect(src, contains("t(context).trArgs('claRpRefundCtx',"));
      expect(src, contains("{'amount': Money.czk(-calc.effectivePriceDiff), 'pct': '\${calc.stornoPercent}'}"));
    });
  });

  group('G-424 open surcharge banner', () {
    Widget pay(Map<String, dynamic> row, double surcharge) => ResPaymentDetailsV2(
          res: resv('s1', status: 'reserved', from: 4, to: 6),
          d: PaymentDetails(row, const []),
          statusLabel: _t('paid'),
          methodLabel: 'Karta',
          card: null,
          paidAt: null,
          stripeTx: null,
          refunded: 0,
          surcharge: surcharge,
          loading: false,
        );

    testWidgets('surcharge due → warn banner with the amount', (t) async {
      final key = GlobalKey();
      await pumpV2(t, SingleChildScrollView(child: pay({'mod_surcharge_due': 1200, 'mod_surcharge_vs': '123'}, 1200)),
          size: const Size(320, 700), boundaryKey: key, overrides: resOverrides(), reducedMotion: true);
      await _frames(t);
      expect(t.takeException(), isNull);
      await maybeShot(t, key, 'clarity_after__surcharge__cs__320');
      expect(find.byKey(const ValueKey('res-pay-surcharge-banner')), findsOneWidget);
      expect(find.textContaining(_t('paySurchargeDue')), findsWidgets);
      expect(find.textContaining(RegExp(r'1\s200')), findsWidgets);
    });

    testWidgets('surcharge paid → no banner', (t) async {
      await pumpV2(t, SingleChildScrollView(child: pay({'mod_surcharge_due': 1200, 'mod_surcharge_paid_at': '2026-11-01'}, 0)),
          overrides: resOverrides(), reducedMotion: true);
      await _frames(t);
      expect(find.byKey(const ValueKey('res-pay-surcharge-banner')), findsNothing);
    });
  });

  for (final (lang, w) in [('cs', 360.0), ('de', 320.0)]) {
  testWidgets('G-643 no swap candidates → state banner with swap.noMoto ($lang $w)', (t) async {
    final key = GlobalKey();
    await pumpV2(
        t,
        SingleChildScrollView(
          child: SwapMotoViewV2(
            rangeText: 'Termín',
            dateText: '2.12.2026',
            onPickDate: () {},
            timePicker: const SizedBox(height: 10),
            currentMotoName: 'Husqvarna 701 SM',
            branchFilter: const SizedBox.shrink(),
            motos: const AsyncValue.data(<Motorcycle>[]),
            candidates: (l) => l,
            avail: const {},
            availLoading: false,
            selectedId: null,
            trailerBlocked: (_) => false,
            onTapMoto: (_, __) {},
            net: null,
            netLoading: false,
            saving: false,
            canConfirm: false,
            onConfirm: () {},
          ),
        ),
        lang: lang,
        size: Size(w, 700),
        boundaryKey: key,
        overrides: resOverrides(),
        reducedMotion: true);
    await _frames(t);
    expect(t.takeException(), isNull);
    final banner = find.byKey(const ValueKey('swap-v2-no-moto'));
    expect(banner, findsOneWidget);
    expect(t.widget(banner), isA<MgStateBanner>());
    expect(find.descendant(of: banner, matching: find.text(translations[lang]!['swap.noMoto']!)), findsOneWidget);
    await maybeShot(t, key, 'clarity_after__swap_no_moto__${lang}__${w.toInt()}');
  });
  }
}
