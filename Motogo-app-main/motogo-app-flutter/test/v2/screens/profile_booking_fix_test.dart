// Profil opened from the booking form ("Doplnit v profilu", profile r3 /
// booking r2 #5/#19): `/profile?edit=personal` pushed over the booking →
// visible back (header + pinned), the personal form opens at the group with
// the first missing field, the fields the booking needs are marked, and
// "Zpět k rezervaci" appears once the SAVED profile satisfies the booking.
// The tab root (and a `go` deep link) stays exactly as before.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/profile/v2/profile_booking_fix_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart' show kBmw, kShotgun;
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_profile.dart';
import '../support/profile_harness.dart';
import '../support/v2_harness.dart';

String _tr(String lang, String k) => translations[lang]?[k] ?? translations['cs']![k]!;

Map<String, dynamic> _profile(Map<String, dynamic> changes) => {...kProfileFull, ...changes};

List<Override> _fix(Map<String, dynamic> profile, Motorcycle moto) => [
      ...profileOverrides(profile: profile),
      bookingMotoProvider.overrideWith((ref) => moto),
    ];

/// The probe for the route helpers (what ProfileScreen's v2 seam calls).
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final back = pfPushedBack(context);
    return Column(children: [
      Text('fix=${pfBookingFixRequested(context)} back=${back != null}'),
      if (back != null) TextButton(onPressed: back, child: const Text('BACK')),
    ]);
  }
}

/// Real frames (the form grows with AnimatedSize, then the page scrolls).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

typedef _Case = ({String name, Map<String, dynamic> profile, Motorcycle moto});

final _cases = <_Case>[
  (name: 'address_missing', profile: _profile({'street': '', 'zip': null}), moto: kBmw),
  (name: 'licence_missing', profile: _profile({'license_number': '', 'license_expiry': null}), moto: kBmw),
  (name: 'licence_group', profile: _profile({'license_group': ['B']}), moto: kShotgun),
  (name: 'expired', profile: _profile({'license_expiry': '2020-01-31'}), moto: kBmw),
  (name: 'complete', profile: kProfileFull, moto: kBmw),
];

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerProfileStrings();
    mockPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('route helpers: pushed over the booking vs tab root vs go deep link', (tester) async {
    final router = GoRouter(initialLocation: '/booking', routes: [
      ShellRoute(builder: (c, s, child) => Material(child: child), routes: [
        GoRoute(
          path: '/booking',
          builder: (c, s) => Builder(
            builder: (c) => TextButton(onPressed: () => c.push('/profile?edit=personal'), child: const Text('BOOKING')),
          ),
        ),
        GoRoute(path: '/profile', pageBuilder: (c, s) => const NoTransitionPage(child: _Probe())),
      ]),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('BOOKING'));
    await tester.pumpAndSettle();
    expect(find.text('fix=true back=true'), findsOneWidget);
    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(find.text('BOOKING'), findsOneWidget, reason: 'back returns to the booking form');

    router.go('/profile');
    await tester.pumpAndSettle();
    expect(find.text('fix=false back=false'), findsOneWidget, reason: 'tab root: no back, no fix');

    router.go('/profile?edit=personal');
    await tester.pumpAndSettle();
    expect(find.text('fix=true back=false'), findsOneWidget, reason: 'go deep link: nothing to go back to');
  });

  testWidgets('address missing: form opens at Adresa, fields marked, back works', (tester) async {
    var backs = 0;
    await pumpV2(tester, PfHubHarness(onBack: () => backs++, bookingFix: true),
        overrides: _fix(_cases[0].profile, kBmw), size: const Size(360, 780));
    await _settle(tester);

    final missing = _tr('cs', 'v2PfFixMissing').replaceAll('{fields}', '${_tr('cs', 'streetShort')}, ${_tr('cs', 'zip')}');
    expect(find.text('$missing\n${_tr('cs', 'v2PfFixHint')}'), findsOneWidget);
    expect(find.text(_tr('cs', 'saveChanges')), findsOneWidget, reason: 'personal form opened');
    expect(find.text(_tr('cs', 'v2PfFixNeeded')), findsNWidgets(2), reason: 'street + zip marked');
    expect(find.text(_tr('cs', 'v2PfFixBack')), findsNothing, reason: 'no way back offered while incomplete');

    final group = find.text(_tr('cs', 'v2PfGroupAddress').toUpperCase());
    final y = tester.getTopLeft(group).dy;
    expect(y, inInclusiveRange(60, 400), reason: 'Adresa scrolled under the pinned back');

    // The pinned back is up (header scrolled away) — still a way back.
    expect(find.byType(MgV2Back), findsWidgets);
    await tester.tap(find.byType(MgV2Back).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(backs, 1);

    // Typing clears the mark live.
    await tester.enterText(find.widgetWithText(TextField, _tr('cs', 'streetShort')), 'Masarykova 12');
    await tester.pump();
    expect(find.text(_tr('cs', 'v2PfFixNeeded')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('licence group: tells the needed category, scrolls to Doklady', (tester) async {
    await pumpV2(tester, PfHubHarness(onBack: () {}, bookingFix: true), overrides: _fix(_cases[2].profile, kShotgun));
    await _settle(tester);
    final text = _tr('cs', 'v2PfFixGroup').replaceAll('{license}', 'A2');
    expect(find.text('$text\n${_tr('cs', 'v2PfFixHint')}'), findsOneWidget);
    expect(find.text(text), findsOneWidget, reason: 'said again right at the licence chips');
    expect(find.text(_tr('cs', 'v2PfFixNeeded')), findsNothing);
    final y = tester.getTopLeft(find.text(_tr('cs', 'v2PfGroupDocs').toUpperCase())).dy;
    expect(y, inInclusiveRange(60, 400));
  });

  testWidgets('expired licence: explains the expiry', (tester) async {
    await pumpV2(tester, PfHubHarness(onBack: () {}, bookingFix: true), overrides: _fix(_cases[3].profile, kBmw));
    await _settle(tester);
    expect(find.text('${_tr('cs', 'v2PfFixExpired')}\n${_tr('cs', 'v2PfFixHint')}'), findsOneWidget);
    expect(find.text(_tr('cs', 'v2PfFixExpired')), findsOneWidget, reason: 'said again right at the expiry date');
  });

  testWidgets('complete: green banner + "Zpět k rezervaci" (banner + under Save)', (tester) async {
    var backs = 0;
    await pumpV2(tester, PfHubHarness(onBack: () => backs++, bookingFix: true), overrides: _fix(kProfileFull, kBmw));
    await _settle(tester);
    expect(find.text(_tr('cs', 'v2PfFixDone')), findsOneWidget);
    expect(find.text(_tr('cs', 'v2PfFixBack')), findsNWidgets(2));
    final y = tester.getTopLeft(find.text(_tr('cs', 'v2PfFixDone'))).dy;
    expect(y, inInclusiveRange(60, 400), reason: 'the green banner is brought into view');
    await tester.tap(find.text(_tr('cs', 'v2PfFixBack')).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(backs, 1);
  });

  testWidgets('tab root (no back): unchanged — collapsed, no banner, no back', (tester) async {
    await pumpV2(tester, const PfHubHarness(bookingFix: true), overrides: _fix(_cases[0].profile, kBmw));
    await _settle(tester);
    expect(find.text(_tr('cs', 'saveChanges')), findsNothing);
    expect(find.text(_tr('cs', 'v2PfFixTitle')), findsNothing);
    expect(find.byType(MgV2Back), findsNothing);
  });

  testWidgets('reduced motion settles', (tester) async {
    await pumpV2(tester, PfHubHarness(onBack: () {}, bookingFix: true),
        overrides: _fix(_cases[0].profile, kBmw), reducedMotion: true);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text(_tr('cs', 'v2PfFixNeeded')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  group('8 langs × 2 sizes, no overflow', () {
    for (final c in _cases) {
      for (final lang in kV2Langs) {
        for (final size in kV2Sizes) {
          testWidgets('${c.name} $lang ${size.width.toInt()}', (tester) async {
            final key = GlobalKey();
            await pumpV2(tester, PfHubHarness(onBack: () {}, bookingFix: true),
                lang: lang, size: size, overrides: _fix(c.profile, c.moto), boundaryKey: key);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
            await expectCleanFrames(tester);
            expect(find.text(_tr(lang, 'saveChanges')), findsOneWidget);
            await maybeShot(tester, key, 'profile__fix__${c.name}__${lang}__${size.width.toInt()}x${size.height.toInt()}');
          });
        }
      }
    }
  });
}
