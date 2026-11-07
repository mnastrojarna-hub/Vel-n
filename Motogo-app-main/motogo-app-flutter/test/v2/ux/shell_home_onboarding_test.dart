// SH-01 first-run language + permission overlays, SH-41 intro, SH-04
// crash screen — v2 look with the SAME callbacks; flag OFF = old overlays.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/overlays/onboarding_overlays.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/shell/v2/crash_view_v2.dart';
import 'package:motogo_app/features/shell/v2/intro_v2.dart';
import 'package:motogo_app/features/shell/v2/onboarding_lang_v2.dart';
import 'package:motogo_app/features/shell/v2/onboarding_perm_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_ux_shell_home.dart' show kOnbLangs, kOnbPerms, shCrash;
import '../support/v2_harness.dart';

class _TestLocale extends LocaleNotifier {
  @override
  Future<void> setLocale(Locale locale, {bool syncProfile = true}) async => state = locale;
}

void main() {
  setUpAll(loadMontserrat);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SH-01 every language tile → onPick with its own code', (tester) async {
    final picked = <String>[];
    await pumpV2(tester, OnboardingLangV2(langs: kOnbLangs, onPick: picked.add), scaffold: false);
    for (final l in kOnbLangs) {
      await tester.ensureVisible(find.byKey(ValueKey('onb-lang-${l.$1}')));
      await tester.tap(find.byKey(ValueKey('onb-lang-${l.$1}')));
      await tester.pump();
    }
    expect(picked, [for (final l in kOnbLangs) l.$1]);
  });

  testWidgets('SH-01 seam: LanguageOverlay v2 → same _selectLang → onDone + prefs', (tester) async {
    var done = 0;
    await pumpV2(tester, LanguageOverlay(onDone: () => done++),
        scaffold: false, overrides: [localeProvider.overrideWith((ref) => _TestLocale())]);
    expect(find.byType(OnboardingLangV2), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onb-lang-cs')));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect((await SharedPreferences.getInstance()).getString('mg_locale'), 'cs');
  });

  testWidgets('SH-01 flag OFF → the old language overlay', (tester) async {
    await pumpV2(tester, LanguageOverlay(onDone: () {}), scaffold: false, v2: false);
    expect(find.byType(OnboardingLangV2), findsNothing);
    expect(find.text('🏍️'), findsOneWidget);
  });

  testWidgets('SH-01 Android permission view: allow / skip / back are the given callbacks', (tester) async {
    final calls = <String>[];
    await pumpV2(
      tester,
      OnboardingPermV2(
        perms: kOnbPerms,
        allowLabel: 'Povolit vše a pokračovat',
        onAllow: () => calls.add('allow'),
        onSkip: () => calls.add('skip'),
        onBack: () => calls.add('back'),
      ),
      scaffold: false,
      reducedMotion: true,
    );
    expect(find.byType(MgCta), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onb-perm-allow')));
    await tester.tap(find.byKey(const ValueKey('onb-perm-skip')));
    await tester.tap(find.byType(MgV2Back));
    await tester.pump();
    expect(calls, ['allow', 'skip', 'back']);
  });

  testWidgets('SH-01 iOS 5.1.1(iv) variant: ONE button, no skip, no back', (tester) async {
    var allow = 0;
    await pumpV2(
      tester,
      OnboardingPermV2(perms: kOnbPerms, allowLabel: 'Pokračovat', onAllow: () => allow++),
      scaffold: false,
      reducedMotion: true,
    );
    expect(find.byType(MgCta), findsOneWidget);
    expect(find.byType(MgBtnText), findsNothing);
    expect(find.byType(MgV2Back), findsNothing);
    expect(find.text('POKRAČOVAT'), findsOneWidget);
    await tester.tap(find.byType(MgCta));
    expect(allow, 1);
  });

  testWidgets('SH-01 seam: Android PermissionOverlay v2 passes its callbacks; flag OFF old', (tester) async {
    final calls = <String>[];
    Widget overlay() => PermissionOverlay(onAllow: () => calls.add('allow'), onSkip: () => calls.add('skip'), onBack: () => calls.add('back'));
    await pumpV2(tester, overlay(), scaffold: false, reducedMotion: true);
    expect(find.byType(OnboardingPermV2), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onb-perm-skip')));
    await tester.tap(find.byType(MgV2Back));
    expect(calls, ['skip', 'back']);
    await pumpV2(tester, overlay(), scaffold: false, v2: false);
    expect(find.byType(OnboardingPermV2), findsNothing);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  testWidgets('SH-41 intro: skip pill → onDone exactly once; plays 2.4 s otherwise', (tester) async {
    var done = 0;
    await pumpV2(tester, IntroV2(onDone: () => done++), scaffold: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('intro-skip')));
    await tester.tap(find.byType(IntroV2), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 3));
    expect(done, 1);

    var auto = 0;
    await pumpV2(tester, IntroV2(key: const ValueKey('b'), onDone: () => auto++), scaffold: false);
    await tester.pump(const Duration(milliseconds: 2300));
    expect(auto, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(auto, 1);
  });

  testWidgets('SH-41 intro reduced motion: end frame, no animation, onDone after 600 ms', (tester) async {
    var done = 0;
    await pumpV2(tester, IntroV2(onDone: () => done++), scaffold: false, reducedMotion: true);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('MOTO GO 24'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 550));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, 1);
  });

  testWidgets('SH-04 crash: MgV2.applied → CrashViewV2 with Zpět / Domů; small box → compact card', (tester) async {
    MgV2.debugSetApplied(true);
    addTearDown(() => MgV2.debugSetApplied(false));
    final calls = <String>[];
    await pumpV2(
      tester,
      CrashViewV2(
        title: 'Tahle obrazovka spadla',
        why: 'x',
        homeLabel: 'Zpět na Domů',
        backLabel: 'Zpět',
        onHome: () => calls.add('home'),
        onBack: () => calls.add('back'),
      ),
      scaffold: false,
      reducedMotion: true,
    );
    expect(find.byType(MgStateScreen), findsOneWidget);
    await tester.tap(find.text('Zpět na Domů'));
    await tester.tap(find.text('Zpět'));
    await tester.tap(find.byType(MgV2Back));
    expect(calls, ['home', 'back', 'home']);

    await pumpV2(tester, SizedBox(height: 120, child: shCrash()), reducedMotion: true);
    expect(find.byType(MgStateScreen), findsNothing);
    expect(find.text('Zpět na Domů'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
