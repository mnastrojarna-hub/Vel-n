// res_profile (RP-06/07/08/09/15/16/17/29): reservation detail fidelity to
// the Reservation board — action tiles call the old callbacks, exactly one
// looping CTA in CO TEĎ per state with the board labels, branch type in the
// meta line, return deadline + rules, loyalty row, status pill countdown,
// self-service timeline nodes, dark rating card inside CO TEĎ, code copy ✓.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/documents/booking_doc_viewer.dart' show BookingDocSource;
import 'package:motogo_app/features/home/v2/home_review_card_v2.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart' show DoorCode;
import 'package:motogo_app/features/reservations/v2/res_action_tiles_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_codes_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_rating_dark_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

Iterable<MgCta> _loopingCtas(WidgetTester t) =>
    t.widgetList<MgCta>(find.byWidgetPredicate((w) => w is MgCta && w.loop));

Widget _detail(Reservation r,
        {List<DoorCode> codes = const [],
        VoidCallback? onCancel,
        Future<void> Function(BuildContext, String)? onInvoice}) =>
    ResDetailV2View(
      res: r,
      doorCodesAsync: AsyncData(codes),
      branchFullAddress: 'Boudky, Velké Němčice',
      onStaleRetry: null,
      onBack: () {},
      onShowCancelDialog: onCancel ?? () {},
      onOpenFinalInvoice: onInvoice ?? (_, __) async {},
      onOpenContract: (_, __) async {},
      onRestoreBooking: (_, __) async {},
    );

Future<void> _pump(WidgetTester t, Widget w,
    {String lang = 'cs', Size size = const Size(360, 780), List<Override>? overrides}) async {
  await pumpV2(t, w, lang: lang, size: size, overrides: overrides ?? resOverrides(), reducedMotion: true);
  await t.pump(const Duration(milliseconds: 600));
}

final _sent = [code('accessories', '4821'), code('motorcycle', '7395')];
const _docs = {'contract': BookingDocSource(signedHtml: '<p>y</p>')};

/// Scrolls [f] to the middle of the viewport (not under the pinned bar).
Future<void> _center(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  Scrollable.ensureVisible(t.element(f), alignment: 0.5);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}
final _held = [code('accessories', '', sent: false), code('motorcycle', '', sent: false)];

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

  group('RP-07 one looping CTA in CO TEĎ', () {
    final cases = <String, (Reservation, List<DoorCode>, List<Override>, String?)>{
      'self-service pickup day': (resv('d1', status: 'reserved', from: 0, to: 2), _sent, resOverrides(), 'v2UxRpProcCta'),
      'docs missing': (resv('d1', status: 'reserved', from: 0, to: 2), _held, resOverrides(), 'uploadDocsForCodes'),
      'staffed upcoming': (
        resv('m1', status: 'reserved', from: 5, to: 7, self: false, bike: 'BMW R 1200 GS Adventure'),
        const <DoorCode>[],
        resOverrides(),
        'navigateToBranch'
      ),
      'active': (resv('d2', status: 'active', from: -1, to: 1, handedOver: rday(-1)), _sent, resOverrides(), 'navigateToBranch'),
      'done': (resv('d5', status: 'completed', from: -6, to: -4), const <DoorCode>[], resOverrides(), 'bookAgain'),
      'cancelled': (resv('d8', status: 'cancelled', from: 10, to: 12), const <DoorCode>[], resOverrides(), 'restoreBooking'),
      'delivery keeps edit': (
        resv('d9', status: 'reserved', from: 4, to: 6, self: false, delivery: true, gear: false),
        const <DoorCode>[],
        resOverrides(),
        'editReservation'
      ),
    };
    for (final e in cases.entries) {
      testWidgets(e.key, (t) async {
        final (r, codes, ov, label) = e.value;
        await _pump(t, _detail(r, codes: codes), overrides: ov);
        final ctas = _loopingCtas(t).toList();
        expect(ctas, hasLength(label == null ? 0 : 1));
        if (label != null) expect(ctas.single.label, _t(label));
      });
    }

    testWidgets('verifying payment: no CTA at all', (t) async {
      final r = resv('d3', status: 'pending', pay: 'unpaid', from: 5, to: 7, self: false, created: DateTime.now());
      await _pump(t, _detail(r),
          overrides: resOverrides(
              pending: PendingBooking(id: r.id, totalPrice: 12027, createdAt: DateTime.now(), verifying: true)));
      expect(_loopingCtas(t), isEmpty);
    });

    testWidgets('self-service: the procedure is the CTA, not a duplicate link', (t) async {
      await _pump(t, _detail(resv('d1', status: 'reserved', from: 0, to: 2), codes: _sent));
      expect(find.text(_t('pickupProcedure')), findsNothing);
    });
  });

  group('RP-06 action tiles', () {
    testWidgets('upcoming: Upravit · Navigovat · Zrušit (red) → the old storno callback', (t) async {
      var cancels = 0;
      await _pump(t, _detail(resv('m1', status: 'reserved', from: 5, to: 7, self: false), onCancel: () => cancels++));
      final tiles = t.widget<ResActionTilesV2>(find.byType(ResActionTilesV2)).tiles;
      expect(tiles.map((x) => x.label), [_t('edit'), _t('v2ResNavigate'), _t('cancel')]);
      expect(tiles.last.destructive, isTrue);
      await _center(t, find.descendant(of: find.byType(ResActionTilesV2), matching: find.text(_t('cancel'))));
      await t.tap(find.descendant(of: find.byType(ResActionTilesV2), matching: find.text(_t('cancel'))));
      expect(cancels, 1);
    });

    testWidgets('active: no storno tile; no Dokumenty without documents', (t) async {
      final r = resv('d2', status: 'active', from: -1, to: 1, handedOver: rday(-1));
      await _pump(t, _detail(r, codes: _sent));
      final labels = t.widget<ResActionTilesV2>(find.byType(ResActionTilesV2)).tiles.map((x) => x.label);
      expect(labels, [_t('edit'), _t('v2ResNavigate')]);
    });

    testWidgets('active with documents: Dokumenty scrolls to the documents section', (t) async {
      final r = resv('d2', status: 'active', from: -1, to: 1, handedOver: rday(-1));
      await _pump(t, _detail(r, codes: _sent), overrides: resOverrides(docs: _docs));
      final tiles = t.widget<ResActionTilesV2>(find.byType(ResActionTilesV2)).tiles;
      expect(tiles.map((x) => x.label), [_t('edit'), _t('v2ResNavigate'), _t('v2UxRpTileDocs')]);
      final docsRow = find.text(_t('rentalContract'));
      final before = t.getTopLeft(docsRow).dy;
      tiles[2].onTap();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(t.getTopLeft(docsRow).dy, lessThan(before));
    });

    testWidgets('done: Hodnotit · Znovu · Faktura (= onOpenFinalInvoice with the booking id)', (t) async {
      String? opened;
      final r = resv('d5', status: 'completed', from: -6, to: -4);
      await _pump(t, _detail(r, onInvoice: (_, id) async => opened = id));
      final tiles = t.widget<ResActionTilesV2>(find.byType(ResActionTilesV2)).tiles;
      expect(tiles.map((x) => x.label), [_t('rateBtn'), _t('v2HomeFnAgain'), _t('invoiceLabel')]);
      tiles[2].onTap();
      await t.pump();
      expect(opened, r.id);
    });

    testWidgets('cancelled: no tiles', (t) async {
      await _pump(t, _detail(resv('d8', status: 'cancelled', from: 10, to: 12)));
      expect(find.byType(ResActionTilesV2), findsNothing);
    });

    testWidgets('2 × 2 grid at 320 de, one row at 412 cs', (t) async {
      final r = resv('d1', status: 'reserved', from: 0, to: 2);
      await _pump(t, _detail(r, codes: _sent), lang: 'de', size: const Size(320, 690), overrides: resOverrides(docs: _docs));
      expect(t.widget<ResActionTilesV2>(find.byType(ResActionTilesV2)).tiles, hasLength(4));
      expect(find.byKey(const ValueKey('res-tiles-grid')), findsOneWidget);
      expect(t.takeException(), isNull);
      await _pump(t, _detail(r, codes: _sent), size: const Size(412, 915), overrides: resOverrides(docs: _docs));
      expect(find.byKey(const ValueKey('res-tiles-grid')), findsNothing);
    });
  });

  group('RP-08 / RP-09 / RP-15 / RP-16 / RP-17 board details', () {
    testWidgets('meta line names the branch type; status pill counts down', (t) async {
      await _pump(t, _detail(resv('m1', status: 'reserved', from: 5, to: 7, self: false)));
      expect(find.text('Supermoto · Mezná · ${_t('v2UxRpTypeStaffed')}'), findsOneWidget);
      expect(find.textContaining('${_t('upcoming').toUpperCase()} · ZA 5 DNÍ'), findsOneWidget);
      await _pump(t, _detail(resv('d2', status: 'active', from: -1, to: 1, handedOver: rday(-1)), codes: _sent));
      expect(find.textContaining('· DEN 2/3'), findsOneWidget);
    });

    testWidgets('return row: deadline + self-service rules incl. the kiosk note', (t) async {
      final r = resv('d1', status: 'reserved', from: 3, to: 5);
      await _pump(t, _detail(r));
      expect(find.textContaining(' do 23:59'), findsWidgets);
      expect(find.text(_t('v2UxRpKioskReturn')), findsOneWidget);
    });

    testWidgets('loyalty row with the rank dot; hidden at 0', (t) async {
      await _pump(t, _detail(resv('d1', status: 'reserved', from: 3, to: 5)));
      await t.ensureVisible(find.text(_t('v2UxRpLoyaltyRow')));
      expect(find.byKey(const ValueKey('res-loyalty-dot')), findsOneWidget);
      final none = Reservation(
        id: 'zzzzzzzz-1111-2222-3333-444455556666',
        motoName: 'Husqvarna 701 SM',
        status: 'reserved',
        paymentStatus: 'paid',
        startDate: rday(3),
        endDate: rday(5),
        totalPrice: 9000,
        loyaltyDiscountAmount: 0,
        createdAt: DateTime.now(),
      );
      await _pump(t, _detail(none));
      expect(find.text(_t('v2UxRpLoyaltyRow')), findsNothing);
    });

    testWidgets('locker door chip on the gear card when the locker code is out', (t) async {
      await _pump(t, _detail(resv('d1', status: 'reserved', from: 0, to: 2), codes: _sent));
      expect(find.text('Šatna · dveře č. 8'), findsOneWidget);
      await _pump(t, _detail(resv('d1', status: 'reserved', from: 3, to: 5)));
      expect(find.text('Šatna · dveře č. 8'), findsNothing);
    });

    testWidgets('self-service timeline: Zaplaceno · Šatna · Protokol · Motorka · Vrácení', (t) async {
      await _pump(t, _detail(resv('d1', status: 'reserved', from: 0, to: 2), codes: _sent));
      for (final k in ['v2ResJPaid', 'v2UxRpJLocker', 'v2UxRpJProtocol', 'v2UxRpJBike', 'v2ResJReturn']) {
        expect(find.text(_t(k)), findsWidgets, reason: k);
      }
      await _pump(t, _detail(resv('m1', status: 'reserved', from: 5, to: 7, self: false)));
      expect(find.text(_t('v2UxRpJProtocol')), findsNothing);
      expect(find.text(_t('v2ResJRide')), findsOneWidget);
    });

    testWidgets('done: dark rating card inside CO TEĎ, no light Home card', (t) async {
      await _pump(t, _detail(resv('d5', status: 'completed', from: -6, to: -4)));
      expect(find.byType(ResRatingDarkV2), findsOneWidget);
      expect(find.byType(HomeReviewLightView), findsNothing);
    });
  });

  testWidgets('RP-29 copy code: ✓ for 1.5 s + selectionClick', (t) async {
    final log = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'HapticFeedback.vibrate') log.add('${c.arguments}');
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(t, _detail(resv('d1', status: 'reserved', from: 0, to: 2), codes: _sent));
    final btn = find.byType(ResCopyCodeV2).first;
    await _center(t, btn);
    await t.tap(btn);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(log, contains('HapticFeedbackType.selectionClick'));
    MgIcon icon() => t.widget<MgIcon>(find.descendant(of: btn, matching: find.byType(MgIcon)));
    expect(icon().name, MgIcons.check);
    await t.pump(const Duration(milliseconds: 1600));
    expect(icon().name, MgIcons.copy);
    await t.pump(const Duration(seconds: 4));
  });
}
