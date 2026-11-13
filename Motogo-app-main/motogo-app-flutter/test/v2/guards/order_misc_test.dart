// Safeguards in the new look, partition "order" (minor gaps): a tap on the
// highlighted tab never leaves the booking form / payment / edit / SOS flow
// (G-346); the Velín banner keeps its Velín colours (G-350); "documents not
// verified" is an amber warning (G-490); scanner warnings look like
// warnings, not like the success line (G-545/G-546); a required but denied
// permission is red (G-752); adding a sized product without a size also
// toasts (G-822).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValue;
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/native/permission_service.dart' show PermissionInfo;
import 'package:motogo_app/core/v2/chrome/mg_top_banner.dart';
import 'package:motogo_app/core/v2/shell/shell_nav_map.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/features/documents/v2/docs_view_v2.dart';
import 'package:motogo_app/features/documents/v2/scan_states_v2.dart';
import 'package:motogo_app/features/profile/v2/permissions_view_v2.dart';
import 'package:motogo_app/features/shop/product_detail_screen.dart';

import '../render/cases_ux_pay_shop.dart' show psShopOverrides;
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import '../support/fakes_docs_scan.dart';
import '../support/ps_harness.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockBookingPathProvider();
  });

  test('G-346: a tap on the active tab is ignored only inside a form / payment / edit / SOS flow', () {
    expect(v2TabTapIgnored(1, '/booking'), isTrue);
    expect(v2TabTapIgnored(1, '/payment?x=1'), isTrue);
    expect(v2TabTapIgnored(2, '/reservations/r1/edit'), isTrue);
    expect(v2TabTapIgnored(2, '/sos/accident'), isTrue);
    expect(v2TabTapIgnored(0, '/booking'), isFalse, reason: 'another tab still switches');
    expect(v2TabTapIgnored(1, '/moto/m-bmw'), isFalse);
    expect(v2TabTapIgnored(2, '/reservations/r1'), isFalse);
  });

  testWidgets('G-350: banner in the Velín colours (inline strip and band)', (t) async {
    const red = Color(0xFFD92D20), white = Color(0xFFFFFFFF);
    await pumpV2(t, const Column(children: [
      MgTopBanner(text: 'Dnes zavřeno', bg: red, fg: white),
      MgTopBanner(text: 'Dnes zavřeno', band: true, bg: red, fg: white),
    ]));
    await t.pump();
    final strip = t.widget<Container>(find.byKey(const ValueKey('mg-top-banner-strip')));
    expect((strip.decoration as BoxDecoration).color, red);
    expect(find.byWidgetPredicate((w) => w is Container && w.color == red), findsOneWidget, reason: 'the band');
    final texts = t.widgetList<Text>(find.text('Dnes zavřeno'));
    expect(texts.every((x) => x.style?.color == white), isTrue);
  });

  testWidgets('G-490: no document at all → amber "not verified" warning', (t) async {
    await pumpV2(
        t,
        DocsViewV2(
          verifiedAsync: AsyncValue.data(st(gate())),
          onBack: () {},
          onScan: () {},
          onScanMissing: () {},
          onScanId: () {},
          onScanDl: () {},
          onUpload: () {},
          onReset: (_) {},
          onRetry: () {},
        ),
        size: const Size(412, 3000));
    await t.pump(const Duration(milliseconds: 50));
    final b = t.widget<MgStateBanner>(find.byKey(const ValueKey('docs-none-warn')));
    // K4-08: the bottom card has its own heading; "Doklady neověřeny" stays
    // as the heading of the status card at the top (shown once).
    expect([b.tone, b.title], [MgTone.warn, _cs.tr('elDocsCodesAfter')]);
    expect(find.text(_cs.tr('docsNotVerified')), findsOneWidget);
  });

  testWidgets('G-545/G-546: a scanner warning is a warning row, the disc turns amber', (t) async {
    await pumpV2(
        t,
        ScanResultV2(
            ok: true,
            side: 'ŘP – zadní strana',
            message: 'Skupiny: A, B\n\n⚠️ Číslo ŘP na zadní straně (X) neodpovídá přední straně (Y).',
            guidance: '',
            remaining: 0,
            onContinue: () {},
            onRetry: () {},
            onSkip: () {}),
        size: const Size(412, 1200));
    await t.pump(const Duration(milliseconds: 400));
    final row = find.byKey(const ValueKey('scan-note-warn'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('neodpovídá')), findsOneWidget);
    expect(t.widget<MgToneDisc>(find.byType(MgToneDisc)).tone, MgTone.warn);
  });

  testWidgets('G-752: required + denied permission → red row and red "Vyžadováno" chip', (t) async {
    const denied = PermissionInfo(key: 'camera', icon: '', title: 'permCameraTitle', desc: 'permCameraDesc', granted: false);
    await pumpV2(
        t,
        PermissionsViewV2(
          perms: const [(denied, true)],
          requiredActive: true,
          bioAvailable: false,
          bioEnabled: false,
          onBack: () {},
          onOpenSettings: () {},
          onBioTap: () {},
          onAllowAll: () {},
        ),
        size: const Size(412, 1600));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('perm-attention-camera')), findsOneWidget);
    final chip = t.widget<MgMeaningChip>(find.byWidgetPredicate((w) => w is MgMeaningChip && w.label == _cs.tr('requiredLabel')));
    expect(chip.tone, MgTone.err);
  });

  testWidgets('G-822: add without a size → inline hint AND a toast', (t) async {
    await pumpPs(t, const ProductDetailScreen(productId: 'p1'), overrides: psShopOverrides());
    await t.tap(find.byKey(const ValueKey('shop-v2-add')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('shop-v2-size-hint')), findsOneWidget);
    expect(find.text(_cs.tr('selectSizeFirst')), findsOneWidget);
  });
}
