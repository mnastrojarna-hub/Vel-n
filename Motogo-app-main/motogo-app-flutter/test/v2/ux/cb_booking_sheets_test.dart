// catalog_booking package · booking sheets: CB-03 size sheets (v2 = same
// SelectedExtra list as the old sheet; drag-down = no change), CB-04 promo
// sheet (same apply / same result text as the old dialog), CB-05 map
// picker (same MapPickerResult, v2 chrome).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_size_dialogs.dart';
import 'package:motogo_app/core/booking_form_promo_section.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_sheet.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/map_picker_chrome_v2.dart';
import 'package:motogo_app/features/booking/widgets/map_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
const _passenger = ExtraCatalogItem(id: 'extra-spolujezdec', name: 'Výbava spolujezdce', price: 0);
const _boots = ExtraCatalogItem(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0, needsSize: true, sizes: ['42', '43', '44']);

/// A button that opens [open] with a live WidgetRef; returns the result box.
Future<List<List<SelectedExtra>>> _host(WidgetTester t, bool v2,
    void Function(BuildContext, WidgetRef, void Function(List<SelectedExtra>)) open) async {
  final out = <List<SelectedExtra>>[];
  await t.pumpWidget(const SizedBox());
  await pumpV2(
    t,
    Consumer(builder: (ctx, ref, _) {
      return Center(child: TextButton(onPressed: () => open(ctx, ref, out.add), child: const Text('OPEN')));
    }),
    overrides: bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)),
    v2: v2,
    reducedMotion: true,
  );
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text('OPEN'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return out;
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
    registerBookingStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('CB-03 passenger sheet: same taps → the same SelectedExtra list as the old sheet', (t) async {
    Future<List<SelectedExtra>> run(bool v2) async {
      final out = await _host(t, v2, (c, ref, cb) => showPassengerGearSheet(c, _passenger, ref, cb));
      expect(find.byType(MgSheetFrame), v2 ? findsOneWidget : findsNothing);
      await _tap(t, find.text('L').first); // helmet
      await _tap(t, find.text('M').at(1)); // gloves
      await _tap(t, find.text(v2 ? _cs.tr('v2UxCbConfirmSizes') : _cs.tr('confirm').toUpperCase()));
      expect(out, hasLength(1));
      return out.single;
    }

    final old = await run(false);
    final neu = await run(true);
    String sig(List<SelectedExtra> l) => l.map((e) => '${e.id}|${e.name}|${e.price}|${e.size}').join(';');
    expect(sig(neu), sig(old));
    expect(neu.single.size, 'Helma: L, Rukavice: M');
  });

  testWidgets('CB-03 passenger sheet: none chosen → confirm locked + amber hint; drag-down = cancel', (t) async {
    final out = await _host(t, true, (c, ref, cb) => showPassengerGearSheet(c, _passenger, ref, cb));
    expect(find.text(_cs.tr('v2UxCbPickOneSize')), findsOneWidget);
    expect(t.widget<MgBtnInk>(find.widgetWithText(MgBtnInk, _cs.tr('v2UxCbConfirmSizes'))).onTap, isNull);
    await _tap(t, find.text('L').first);
    expect(find.text(_cs.tr('v2UxCbPickOneSize')), findsNothing);
    await t.drag(find.byType(MgSheetFrame), const Offset(0, 600));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(MgSheetFrame), findsNothing);
    expect(out, isEmpty);
  });

  testWidgets('CB-03 boots sheet: tap = pick + close (old rule); "Odebrat" only for a chosen extra', (t) async {
    Future<List<SelectedExtra>> run(bool v2) async {
      final out = await _host(t, v2, (c, ref, cb) => showSizeDialog(c, _boots, ref, cb));
      expect(find.text(_cs.tr('removeBtn')), findsNothing);
      await _tap(t, find.text('43'));
      return out.single;
    }

    final old = await run(false);
    final neu = await run(true);
    expect([neu.single.id, neu.single.size, neu.single.price], [old.single.id, old.single.size, old.single.price]);
    final current = SelectedExtra(id: _boots.id, name: _boots.name, price: 0, size: '43');
    final out = await _host(t, true, (c, ref, cb) => showSizeDialog(c, _boots, ref, cb, current: current));
    final remove = find.widgetWithText(MgBtnText, _cs.tr('removeBtn'));
    expect(remove, findsOneWidget);
    await _tap(t, remove);
    expect(out.single.where((e) => e.id == _boots.id), isEmpty);
  });

  testWidgets('CB-04 promo: the sheet runs the same check and shows the same reason as the old dialog', (t) async {
    final applied = [AppliedDiscount(code: 'JARO10', type: DiscountType.percent, value: 10)];
    Future<String> run(bool v2) async {
      await t.pumpWidget(const SizedBox());
      await pumpV2(
        t,
        SingleChildScrollView(
          child: Consumer(
            builder: (_, ref, __) => BookingFormPromoSection(
              draft: ref.watch(bookingDraftProvider),
              onUpd: (fn) => ref.read(bookingDraftProvider.notifier).state = fn(ref.read(bookingDraftProvider)),
            ),
          ),
        ),
        overrides: [
          ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, discounts: applied)),
          myVouchersProvider.overrideWith((ref) async => const <MyVoucher>[]),
        ],
        v2: v2,
        reducedMotion: true,
      );
      await t.pump(const Duration(milliseconds: 300));
      await _tap(t, find.text(v2 ? _cs.tr('v2BkPromoAdd') : _cs.tr('clickEnterCode')).first);
      expect(find.byType(MgSheetFrame), v2 ? findsOneWidget : findsNothing);
      await t.enterText(find.byType(TextField), 'jaro10');
      await _tap(t, find.text(v2 ? _cs.tr('apply') : _cs.tr('apply').toUpperCase()));
      final msg = _cs.tr('promoAlreadyUsed').replaceAll('{code}', 'jaro10');
      expect(find.text(msg), findsOneWidget);
      if (v2) expect(find.byType(MgStateBanner), findsOneWidget);
      return msg;
    }

    expect(await run(true), await run(false));
  });

  testWidgets('CB-05 map picker: v2 chrome (back, one ink confirm) returns the same MapPickerResult', (t) async {
    Future<MapPickerResult?> run(bool v2) async {
      MapPickerResult? got;
      await t.pumpWidget(const SizedBox());
      await pumpV2(t, Builder(builder: (ctx) {
        return Center(
          child: TextButton(
            onPressed: () async => got = await MapPickerScreen.show(ctx, lat: 49.4, lng: 15.2),
            child: const Text('OPEN'),
          ),
        );
      }), v2: v2, reducedMotion: true);
      await t.tap(find.text('OPEN'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(MapPickerChromeV2), v2 ? findsOneWidget : findsNothing);
      if (v2) {
        expect(find.byType(MgV2Back), findsOneWidget);
        expect(find.byType(MgBtnInk), findsOneWidget);
        expect(find.text('📍'), findsNothing);
      }
      await t.tap(find.textContaining(_cs.tr('confirmAddressAction')).last);
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpWidget(const SizedBox());
      // Geocoding timeouts (4 s / 5 s) and the tile-error note (30 s) run out.
      await t.pump(const Duration(seconds: 31));
      return got;
    }

    final old = await run(false);
    final neu = await run(true);
    expect(neu, isNotNull);
    expect([neu!.lat, neu.lng, neu.street, neu.city, neu.zip, neu.fullAddress],
        [old!.lat, old.lng, old.street, old.city, old.zip, old.fullAddress]);
  });
}
