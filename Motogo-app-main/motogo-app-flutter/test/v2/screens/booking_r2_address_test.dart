// fix:booking:r2 — the address sheet never saves an address with a stale
// delivery price: POTVRDIT while a picked address (one-tap quick option,
// suggestion, GPS) is still being routed waits for its price; picking and
// closing the sheet without POTVRDIT changes neither address nor price.
// Shared sheet (both trees); here through the booking form's pickup section.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/price_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/v2_harness.dart';

String _tr(String key) => translations['cs']![key]!;

/// Slow network: every lookup answers after 1 s with "not found", so the
/// picked profile address falls back to the city estimate.
Future<void> _slowNet(Future<void> Function() body) => http.runWithClient(
    body,
    () => MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response('{}', 404);
        }));

Future<ProviderContainer> _openSheet(WidgetTester t) async {
  await pumpV2(t, const BookingDebugWrapper(),
      size: const Size(412, 915),
      overrides: bookingOverrides(
          moto: kBmw,
          draft: bookingDraft(kBmw, pickupMethod: 'delivery')
              .copyWith(pickupCity: () => null, pickupAddress: () => null)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  final c = ProviderScope.containerOf(t.element(find.byType(BookingDebugWrapper)));
  final open = find.text(_tr('v2BkEnterAddress')).first;
  await t.ensureVisible(open);
  await t.pump();
  await t.tap(open);
  await _steps(t, 3);
  return c;
}

Future<void> _steps(WidgetTester t, int n) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerBookingStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });
  final fee = PriceCalculator.calcDeliveryFee(estimateKm('Pelhřimov').toDouble());

  testWidgets('quick option + immediate POTVRDIT saves the address WITH its routed price', (t) => _slowNet(() async {
        final c = await _openSheet(t);
        await t.tap(find.text(_tr('bkAddrMine')));
        await t.pump(const Duration(milliseconds: 50));
        // Still routing — the old sheet saved here with the old price (0).
        expect(find.text(_tr('calculatingKm')), findsOneWidget);
        await t.tap(find.text(_tr('confirmAddressBtn')));
        await t.pump(const Duration(milliseconds: 50));
        expect(c.read(bookingDraftProvider).pickupCity, isNull, reason: 'waits for the price');
        await _steps(t, 8);
        expect(find.byType(TextField), findsNothing, reason: 'sheet closed after saving');
        expect(c.read(bookingDraftProvider).pickupCity, 'Pelhřimov');
        expect(c.read(pickupDelivFeeProvider), fee);
        expect(fee, greaterThan(0));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 2));
      }));

  testWidgets('pick, then close without POTVRDIT: address and price unchanged', (t) => _slowNet(() async {
        final c = await _openSheet(t);
        await t.tap(find.text(_tr('bkAddrMine')));
        await _steps(t, 6);
        expect(find.textContaining(' km · '), findsOneWidget, reason: 'the sheet shows the price');
        Navigator.of(t.element(find.byType(TextField))).pop();
        await _steps(t, 3);
        expect(find.byType(TextField), findsNothing);
        expect(c.read(bookingDraftProvider).pickupCity, isNull);
        expect(c.read(pickupDelivFeeProvider), 0);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 2));
      }));
}
