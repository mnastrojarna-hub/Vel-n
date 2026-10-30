// fix:booking:r3 — (1) licence / overlap errors in the app language (shared
// validator, both trees; before: always Czech); (2) v2 look of the address
// sheet (Android only): lineInput field, white rows, GPS / Mapa ghost
// buttons, ONE ink „Potvrdit adresu“, ✕ 44 — the same actions as before.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_validator.dart';
import 'package:motogo_app/features/booking/v2/addr_sheet_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/render_inspect.dart';
import '../support/fakes_booking.dart';
import '../support/fakes_reservations.dart' show resv;
import '../support/v2_harness.dart';

String _tr(String lang, String key) => translations[lang]![key]!;

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(String lang) {
    state = Locale(lang);
  }
}

final _booked = resv('a2', status: 'reserved', from: 6, to: 8, self: false, bike: 'BMW R 1200 GS Adventure');

String? _overlap(String lang) => BookingValidator.checkOverlap(
      userReservations: [_booked],
      startDate: _booked.startDate,
      endDate: _booked.endDate,
      isChildrensMoto: false,
      lang: lang,
    );

/// Every lookup answers "not found" (after [delay]) → city estimate.
Future<void> _net(Future<void> Function() body, {Duration delay = Duration.zero}) => http.runWithClient(
    body,
    () => MockClient((_) async {
          await Future<void>.delayed(delay);
          return http.Response('{}', 404);
        }));

Future<void> _openSheet(WidgetTester t,
    {String lang = 'cs', Size size = const Size(412, 915), bool v2 = true, GlobalKey? shot}) async {
  await pumpV2(t, const BookingDebugWrapper(),
      boundaryKey: shot,
      lang: lang,
      size: size,
      v2: v2,
      reducedMotion: true,
      overrides: bookingOverrides(
          moto: kBmw,
          draft: bookingDraft(kBmw, pickupMethod: 'delivery')
              .copyWith(pickupCity: () => null, pickupAddress: () => null)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  final open = find.text(_tr(lang, v2 ? 'v2BkEnterAddress' : 'clickEnterAddress')).first;
  await Scrollable.ensureVisible(t.element(open), alignment: 0.4);
  await t.pump();
  await t.tap(open);
  for (var i = 0; i < 3; i++) {
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

  group('licence / overlap errors follow the app language', () {
    for (final lang in kV2Langs) {
      test(lang, () {
        expect(
            BookingValidator.checkLicense(userLicenseGroups: ['B'], motoLicenseGroups: ['A'], lang: lang),
            _tr(lang, 'validationInsufficientLicense').replaceAll('{groups}', 'B').replaceAll('{license}', 'A'));
        expect(BookingValidator.checkLicense(userLicenseGroups: const [], motoLicenseGroups: ['A2'], lang: lang),
            _tr(lang, 'validationNoLicense').replaceAll('{license}', 'A2'));
        final o = _overlap(lang)!;
        expect(o, contains('BMW R 1200 GS Adventure'));
        expect(o, startsWith(_tr(lang, 'validationOverlap').split('{start}').first));
        if (lang != 'cs') expect(o, isNot(_overlap('cs')));
      });
    }

    test('default and unknown language stay Czech; OK cases stay null', () {
      final cs = BookingValidator.checkLicense(userLicenseGroups: ['B'], motoLicenseGroups: ['A']);
      expect(cs, startsWith('Vaše řidičské oprávnění'));
      expect(BookingValidator.checkLicense(userLicenseGroups: ['B'], motoLicenseGroups: ['A'], lang: 'xx'), cs);
      expect(BookingValidator.checkLicense(userLicenseGroups: ['A'], motoLicenseGroups: ['A2'], lang: 'en'), isNull);
      expect(
          BookingValidator.checkOverlap(
              userReservations: [_booked],
              startDate: _booked.startDate,
              endDate: _booked.endDate,
              isChildrensMoto: true,
              lang: 'en'),
          isNull);
    });

    test('licenseValidationProvider uses localeProvider', () async {
      final c = ProviderContainer(overrides: [
        ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: const {'license_group': ['B']}),
        localeProvider.overrideWith((ref) => _FixedLocale('de')),
      ]);
      addTearDown(c.dispose);
      await c.read(profileProvider.future);
      expect(c.read(licenseValidationProvider), startsWith('Ihr Führerschein (B)'));
    });
  });

  group('address sheet v2 look', () {
    testWidgets('v2: ink confirm, ghost GPS / Mapa, ✕ 44, no old buttons; same quick-option flow',
        (t) => _net(() async {
              final shot = GlobalKey();
              await _openSheet(t, shot: shot);
              final sheet = find.byType(AddrSheetV2View);
              expect(sheet, findsOneWidget);
              Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
              expect(inSheet(find.byType(OutlinedButton)), findsNothing);
              expect(inSheet(find.byType(ElevatedButton)), findsNothing);
              expect(inSheet(find.byType(MgBtnInk)), findsOneWidget);
              expect(inSheet(find.byType(MgBtnGhostLight)), findsNWidgets(2));
              expect(find.text(_tr('cs', 'v2AddrConfirm')), findsOneWidget);
              expect(find.text(_tr('cs', 'confirmAddressBtn')), findsNothing);
              expect(find.text(_tr('cs', 'v2AddrHint')), findsOneWidget);
              final close = inSheet(find.byType(MgV2Back));
              expect(close, findsOneWidget);
              expect(t.getSize(close).height, greaterThanOrEqualTo(44));
              await t.tap(inSheet(find.text(_tr('cs', 'bkAddrMine'))));
              await t.pump(const Duration(milliseconds: 50));
              expect(find.text(_tr('cs', 'calculatingKm')), findsOneWidget);
              for (var i = 0; i < 6; i++) {
                await t.pump(const Duration(milliseconds: 300));
              }
              expect(find.textContaining(' km · '), findsOneWidget);
              expect(inSheet(find.text(_tr('cs', 'bkAddrMine'))), findsNothing);
              await maybeShot(t, shot, 'booking_addr_sheet_picked__cs__412');
              await t.tap(close);
              for (var i = 0; i < 3; i++) {
                await t.pump(const Duration(milliseconds: 300));
              }
              expect(sheet, findsNothing, reason: '✕ closes without saving');
              await t.pumpWidget(const SizedBox());
              await t.pump(const Duration(seconds: 2));
            }, delay: const Duration(seconds: 1)));

    testWidgets('flag off: the old sheet is unchanged', (t) => _net(() async {
          await _openSheet(t, v2: false);
          expect(find.byType(AddrSheetV2View), findsNothing);
          expect(find.text(_tr('cs', 'confirmAddressBtn')), findsOneWidget);
          expect(find.byType(OutlinedButton), findsWidgets);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 2));
        }));

    for (final lang in kV2Langs) {
      for (final size in const [Size(320, 690), ...kV2Sizes]) {
        testWidgets('$lang ${size.width.toInt()}', (t) => _net(() async {
              final shot = GlobalKey();
              await _openSheet(t, lang: lang, size: size, shot: shot);
              expect(t.takeException(), isNull);
              await maybeShot(t, shot, 'booking_addr_sheet__${lang}__${size.width.toInt()}');
              expect(find.text(_tr(lang, 'v2AddrConfirm')), findsOneWidget);
              expect(find.text(_tr(lang, 'v2AddrHint')), findsOneWidget);
              final fails = inspectFrame(t.binding.renderViews.first, lang, size).where((f) => f.fail);
              expect(fails.map((f) => '${f.kind} "${f.text}" ${f.detail}'), isEmpty);
              await t.pumpWidget(const SizedBox());
              await t.pump(const Duration(seconds: 2));
            }));
      }
    }
  });
}
