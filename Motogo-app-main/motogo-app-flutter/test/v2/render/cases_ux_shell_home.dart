// verify:render cases — shell_home package (SH-*): first-run overlays,
// offline overlay + strips, update dialogs, crash screen, push banner,
// "+n" strips sheet, Home club disclosure open, tier preview sheet. Home
// states themselves come from cases_home.dart (HomeScreenV2).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/widgets/mg_dialog.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_tier_preview_v2.dart';
import 'package:motogo_app/features/shell/v2/crash_view_v2.dart';
import 'package:motogo_app/features/shell/v2/intro_v2.dart';
import 'package:motogo_app/features/shell/v2/offline_view_v2.dart';
import 'package:motogo_app/features/shell/v2/onboarding_lang_v2.dart';
import 'package:motogo_app/features/shell/v2/onboarding_perm_v2.dart';
import 'package:motogo_app/features/shell/v2/push_banner_v2.dart';
import 'package:motogo_app/features/shell/v2/update_dialog_v2.dart';

import '../support/fakes_home.dart';
import 'cases_core.dart' show launcher, tapOpen;
import 'render_harness.dart';

const kOnbLangs = [
  ('cs', 'Čeština'),
  ('en', 'English'),
  ('de', 'Deutsch'),
  ('pl', 'Polski'),
  ('fr', 'Français'),
  ('es', 'Español'),
  ('nl', 'Nederlands'),
  ('uk', 'Українська'),
];

const kOnbPerms = [
  ('permLocationTitle', 'permLocationDesc'),
  ('permCameraTitle', 'permCameraDesc'),
  ('permMicTitle', 'permMicDesc'),
  ('permNotifTitle', 'permNotifDesc'),
  ('permPhotosTitle', 'permPhotosDesc'),
  ('obBiometricTitle', 'obBiometricDesc'),
];

Widget shOnbLang() => OnboardingLangV2(langs: kOnbLangs, onPick: (_) {});

Widget shOnbPerm({bool ios = false}) => Builder(
      builder: (c) => OnboardingPermV2(
        perms: kOnbPerms,
        allowLabel: t(c).tr(ios ? 'next' : 'v2UxShPermAllow'),
        onAllow: () {},
        onSkip: ios ? null : () {},
        onBack: ios ? null : () {},
      ),
    );

Widget shOffline({bool still = false}) =>
    OfflineViewV2(checking: false, stillOffline: still, onRetry: () {}, onContinue: () {}, onCall112: () {});

Widget shStrip(bool offline) => Stack(children: [const Positioned.fill(child: ColoredBox(color: Color(0xFFF4F7F5))), OfflineStripV2(offline: offline)]);

Widget shCrash() => Builder(
      builder: (c) => CrashViewV2(
        title: t(c).tr('v2UxShCrashTitle'),
        why: t(c).tr('v2UxShCrashWhy'),
        homeLabel: t(c).tr('v2UxShCrashHome'),
        backLabel: t(c).tr('eoBack'),
        onHome: () {},
        onBack: () {},
      ),
    );

void shOpenForce(BuildContext c, {bool failed = false}) => showDialog<void>(
      context: c,
      barrierDismissible: false,
      builder: (_) => UpdateForceDialogV2(version: '4.3.0', storeFailed: failed, onUpdate: () {}, onCall: () {}, onCall112: () {}),
    );

void shOpenOffer(BuildContext c) => showMgDialog<void>(c,
    builder: (ctx) => UpdateOfferDialogV2(version: '4.3.0', onLater: () => Navigator.of(ctx).pop(), onUpdate: () {}));

void shOpenPush(BuildContext c, {required bool codes}) => ScaffoldMessenger.of(c).showSnackBar(pushBannerSnackV2(
      title: codes ? 'Přístupové kódy k pobočce' : 'Nová zpráva od MotoGo24',
      body: codes
          ? 'Pobočka Mezná: kód motorky 4821, kód šatny 1934, platí pá 16. 10. 9:00 – ne 18. 10. 23:59.'
          : 'Dobrý den, motorka je připravená, těšíme se na vás.',
      doorCodes: codes,
      viewLabel: 'Zobrazit',
      closeLabel: 'Zavřít',
      onView: () {},
      onClose: () {},
    ));

Future<void> _openClub(WidgetTester t) async {
  final f = find.byKey(const ValueKey('home-club-more'));
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(find.descendant(of: f, matching: find.byType(GestureDetector)).first);
  await t.pump(const Duration(milliseconds: 400));
}

List<RenderCase> shellHomeUxCases() => [
      RenderCase('shux', 'onb', 'lang', shOnbLang, () => const [], scaffold: false),
      RenderCase('shux', 'onb', 'perm_android', shOnbPerm, () => const [], scaffold: false),
      RenderCase('shux', 'onb', 'perm_ios', () => shOnbPerm(ios: true), () => const [], scaffold: false),
      RenderCase('shux', 'onb', 'intro', () => IntroV2(onDone: () {}), () => const [], scaffold: false),
      RenderCase('shux', 'offline', 'overlay', shOffline, () => const [], scaffold: false),
      RenderCase('shux', 'offline', 'still', () => shOffline(still: true), () => const [], scaffold: false),
      RenderCase('shux', 'offline', 'strip_offline', () => shStrip(true), () => const [], scaffold: false),
      RenderCase('shux', 'offline', 'strip_wifi', () => shStrip(false), () => const [], scaffold: false),
      RenderCase('shux', 'update', 'force', () => launcher(shOpenForce), () => const [], after: tapOpen),
      RenderCase('shux', 'update', 'force_fail', () => launcher((c) => shOpenForce(c, failed: true)), () => const [], after: tapOpen),
      RenderCase('shux', 'update', 'offer', () => launcher(shOpenOffer), () => const [], after: tapOpen),
      RenderCase('shux', 'crash', 'full', shCrash, () => const [], scaffold: false),
      RenderCase('shux', 'push', 'codes', () => launcher((c) => shOpenPush(c, codes: true)), () => const [], after: tapOpen),
      RenderCase('shux', 'push', 'message', () => launcher((c) => shOpenPush(c, codes: false)), () => const [], after: tapOpen),
      RenderCase('shux', 'home', 'club_open', () => const HomeScreenV2(), () => homeOverrides(), after: _openClub),
      RenderCase('shux', 'sheet', 'tier_preview', () => launcher((c) => showTierPreviewSheet(c, 17)), () => homeOverrides(),
          after: tapOpen, level: 17),
    ];
