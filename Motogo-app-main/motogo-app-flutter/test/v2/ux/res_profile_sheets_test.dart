// res_profile sheets / viewers / small screens (RP-03/04/05/13/14/20/21/22/25):
// document viewer chrome (✕ = the same close, long titles never ellipsized,
// A4 skeleton with the 15 s "takes longer" state), ride feedback v2 sheet,
// "Motorky na pobočkách" v2 sheet, branch card "Rezervovat zde", cancel
// dialog copy, invoice amounts, profile header skeleton, notification row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_support_row.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/features/branches/v2/branch_moto_row_v2.dart';
import 'package:motogo_app/features/documents/document_models.dart';
import 'package:motogo_app/features/documents/invoices_screen.dart';
import 'package:motogo_app/features/documents/v2/doc_viewer_chrome_v2.dart';
import 'package:motogo_app/features/profile/v2/branches_sheet_v2.dart';
import 'package:motogo_app/features/profile/v2/profile_groups_v2.dart';
import 'package:motogo_app/features/profile/v2/profile_header_v2.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart' show CancelResult;
import 'package:motogo_app/features/reservations/v2/res_cancel_v2.dart';
import 'package:motogo_app/features/reservations/v2/ride_feedback_sheet_v2.dart';
import 'package:motogo_app/features/reservations/widgets/cancel_result_dialog.dart';
import 'package:motogo_app/features/reservations/widgets/ride_feedback_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_profile.dart';
import '../support/fakes_reservations.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

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

  group('RP-03 document viewer chrome', () {
    testWidgets('✕ runs the same close; long title on two lines, never ellipsized (320 de)', (t) async {
      var closed = 0;
      const title = 'Übergabeprotokoll Husqvarna 701 SM Supermoto Velké Němčice';
      await pumpV2(t, DocViewerScaffoldV2(title: title, onClose: () => closed++, body: const SizedBox()),
          lang: 'de', size: const Size(320, 690), scaffold: false);
      await t.pump();
      final back = t.widget<MgV2Back>(find.byType(MgV2Back));
      expect(back.close, isTrue);
      await t.tap(find.byType(MgV2Back));
      expect(closed, 1);
      final text = t.widget<Text>(find.text(title));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.visible);
      expect(t.takeException(), isNull);
    });

    testWidgets('A4 skeleton, then "takes longer" + retry after 15 s', (t) async {
      var retries = 0;
      await pumpV2(t, DocA4SkeletonV2(onRetry: () => retries++, onBack: () {}));
      await t.pump();
      expect(find.text(_t('eoSlowTitle')), findsNothing);
      await t.pump(const Duration(seconds: 15));
      expect(find.text(_t('eoSlowTitle')), findsOneWidget);
      await t.tap(find.text(_t('eoRetry')));
      expect(retries, 1);
    });
  });

  group('RP-04 ride feedback sheet', () {
    testWidgets('v2 sheet: empty send explains under the field; ✕ closes with no thread', (t) async {
      String? result = 'unset';
      await pumpV2(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async => result =
                await showRideFeedbackSheet(c, res: resv('d5', status: 'completed', from: -6, to: -4), rating: 2),
            child: const Text('open'),
          ),
        ),
        overrides: resOverrides(),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(RideFeedbackSheetV2), findsOneWidget);
      await t.tap(find.text(_t('send')));
      await t.pump();
      expect(find.text(_t('rfEmpty')), findsOneWidget);
      expect(find.byType(RideFeedbackSheetV2), findsOneWidget);
      await t.tap(find.byType(MgV2Back));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(RideFeedbackSheetV2), findsNothing);
      expect(result, isNull);
    });
  });

  testWidgets('RP-05 branches sheet: card expands to details, navigation and bikes', (t) async {
    final branches = [
      {'id': 'b1', 'name': 'MotoGo24 Mezná', 'address': 'Mezná 9', 'city': 'Pelhřimov', 'type': 'obslužná', 'is_open': true,
        'phone': '+420774256271', 'gps_lat': 49.4, 'gps_lng': 15.2},
    ];
    final motos = {
      'b1': [
        {'id': 'm1', 'model': 'BMW R 1200 GS Adventure', 'brand': 'BMW', 'engine_cc': 1170, 'power_kw': 92, 'license_required': 'A'},
      ],
    };
    await pumpV2(t, SingleChildScrollView(child: BranchesSheetV2(branches: branches, motosByBranch: motos)));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text(_t('navigateToBranch')), findsNothing);
    await t.tap(find.text('MotoGo24 Mezná'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_t('navigateToBranch')), findsOneWidget);
    expect(find.byType(BranchMotoRowV2), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('RP-21 cancel flow copy', () {
    testWidgets('confirm: "Nechat rezervaci" + readable rules', (t) async {
      await pumpV2(t, ResCancelConfirmV2(
        motoName: 'Husqvarna 701 SM',
        dateRange: 'pá 16. 10. – ne 18. 10.',
        pct: 50,
        refundLine: 'Teď ti vrátíme 6 014 Kč (50 %)',
        loading: false,
        onReason: (_) {},
        onKeep: () {},
        onCancel: () {},
      ));
      await t.pump();
      expect(find.text(_t('v2UxRpKeepRes')), findsOneWidget);
      for (final k in ['v2UxRpStorno100', 'v2UxRpStorno50', 'v2UxRpStorno0']) {
        expect(find.text(_t(k)), findsOneWidget);
      }
    });

    testWidgets('done: refund with NBSP amount, gender-neutral; failure offers a call', (t) async {
      await pumpV2(t, Builder(
        builder: (c) => cancelResultDialog(c, const CancelResult.success(50, 6014),
            wasPaid: true, onClose: () {}, onRetry: () {}),
      ));
      await t.pump();
      expect(find.textContaining('kterou se platilo'), findsOneWidget);
      expect(find.textContaining('6 014'), findsOneWidget);
      await pumpV2(t, Builder(
        builder: (c) => cancelResultDialog(c, const CancelResult.failure('network'),
            wasPaid: true, onClose: () {}, onRetry: () {}),
      ));
      await t.pump();
      expect(find.byType(MgSupportRow), findsOneWidget);
    });
  });

  testWidgets('RP-22 invoice row: type as title, "number · date", "12 027 Kč"', (t) async {
    await pumpV2(t, InvoiceTile(
      invoice: UserInvoice(id: 'i1', number: 'ZF-2026-0142', type: 'advance', total: 12027, createdAt: DateTime(2026, 9, 30)),
    ));
    await t.pump();
    expect(find.text('12 027 Kč'), findsOneWidget);
    expect(find.text('ZF-2026-0142 · 30. 9. 2026'), findsOneWidget);
  });

  group('RP-13 / RP-25 profile', () {
    testWidgets('header while loading: skeleton bars, never "Pilot"', (t) async {
      await pumpV2(t, ProfileHeaderV2(profile: null, onSettings: () {}, loading: true), overrides: profileOverrides());
      await t.pump();
      expect(find.byKey(const ValueKey('pf-header-skeleton')), findsOneWidget);
      expect(find.text(_t('pilot')), findsNothing);
    });

    testWidgets('Notifikace shows the enabled channels from the loaded profile', (t) async {
      const actions = PfGroupActions(
        onPermissions: _noop, onNotif: _noop, onPrivacy: _noop, onPassword: _noop, onLanguage: _noop,
        onCurrency: _noop, onFaq: _noop, onLogout: _noop, onDelete: _noop,
      );
      await pumpV2(
        t,
        SingleChildScrollView(child: ProfileGroupsV2(actions: actions, settingsKey: GlobalKey(), version: '4.2.0')),
        overrides: profileOverrides(profile: {...kProfileFull, 'consent_push': true, 'consent_email': true, 'consent_sms': false}),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Push · E-mail'), findsOneWidget);
    });
  });
}

void _noop() {}
