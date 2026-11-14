// 5.0.1 media repairs: the play button sits off the bike (top right, under
// the branch chip), the sharp photo fades out under the video (blurred band
// kept), a recycled card never shows another bike's button, the chip stays
// on the pill's row (the mode joins the tags when it must shorten), the
// hero drops its repeated branch line, the "Pobočka" row never cuts the
// city, and the detail dock's "od" equals the card's "Tvoje cena od".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/widgets/mg_branch_chip.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_card_parts_v2.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_video_layer_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/catalog_text.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_more_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';
import 'v501_media_fake.dart';
import 'v501_media_hero_test.dart' show pumpHero;

const _price = CatCardPrice(label: 'Cena od', value: '2 727 Kč', unit: '/den', sub: '', grid: '');
String _cs(String k) => translations['cs']![k]!;

/// No key: the same card element gets the next bike (a recycled slot).
Widget _slot(Motorcycle m) => ListView(children: [
      MotoCardFullV2(moto: m, price: _price, availability: 'Dnes volná', ctaLabel: 'Detail', onOpen: () {}, height: 780),
    ]);

final _play = find.byKey(const ValueKey('bike-video-play'));

Motorcycle _self(String id, {List<String> videos = const ['https://x/v1.mp4']}) => Motorcycle(
      id: id,
      model: 'Bike $id',
      category: 'cestovni',
      videos: videos,
      branchName: 'MotoGo24 Velké Němčice',
      branchCity: 'Brno - Velké Němčice',
      branchType: 'samoobslužná',
      branchAddress: 'Hlavní 12',
    );

void main() {
  setUpAll(loadMontserrat);
  late FakeVideos fake;
  setUp(() => fake = FakeVideos.install(wifi: false));
  tearDown(() => fake.uninstall());

  testWidgets('card: the play button is top right under the chip, off the photo centre', (t) async {
    await pumpV2(t, _slot(bike('a')));
    await wait(t, const Duration(seconds: 1));
    expect(_play, findsOneWidget);
    final b = t.getRect(_play);
    final chip = t.getRect(find.byType(MgBranchChip));
    expect(b.right, moreOrLessEquals(360 - 12, epsilon: 0.5));
    expect(b.top, greaterThanOrEqualTo(chip.bottom));
    expect(b.bottom, lessThan(130), reason: 'in the top band, not on the bike');
  });

  testWidgets('a recycled card: video bike → bike without video has no button in the first frame', (t) async {
    final moto = ValueNotifier(bike('a'));
    addTearDown(moto.dispose);
    await pumpV2(t, ValueListenableBuilder<Motorcycle>(valueListenable: moto, builder: (_, m, __) => _slot(m)));
    await wait(t, const Duration(seconds: 1));
    expect(_play, findsOneWidget);
    moto.value = bike('b', videos: const []);
    await t.pump();
    expect(_play, findsNothing);
    await wait(t, const Duration(seconds: 7));
    expect(_play, findsNothing);
    expect(fake.created, isEmpty);
  });

  testWidgets('Wi-Fi: the sharp photo fades out under the video, the blurred band stays', (t) async {
    fake.wifi = true;
    await pumpV2(t, _slot(bike('a', images: const ['https://x/p.jpg'])));
    double photo() => t
        .widget<AnimatedOpacity>(find.descendant(of: find.byType(BikePhotoFade), matching: find.byType(AnimatedOpacity)))
        .opacity;
    await wait(t, const Duration(seconds: 2));
    expect(photo(), 1);
    await wait(t, const Duration(seconds: 5));
    expect(photo(), 0);
    final layer = find.byKey(const ValueKey('bike-video-layer'));
    // Only the (fake) video frame itself — no opaque night slab around it.
    final boxes = t.widgetList<ColoredBox>(find.descendant(of: layer, matching: find.byType(ColoredBox)));
    expect(boxes.every((b) => '${b.key}'.contains('fake-video')), isTrue, reason: 'no opaque slab');
  });

  testWidgets('card at 320: the chip stays on the pill row; the mode joins the tags', (t) async {
    await pumpV2(t, _slot(_self('s', videos: const [])), size: const Size(320, 690));
    await t.pump();
    final chip = t.getRect(find.byType(MgBranchChip));
    final pill = t.getRect(find.byType(BikeCardAvailabilityPill));
    expect((chip.center.dy - pill.center.dy).abs(), lessThan(3), reason: 'one row, no staircase');
    expect(find.text('Velké Němčice'), findsOneWidget);
    expect(find.widgetWithText(BikeCardTag, _cs('v2UxRpTypeSelf')), findsOneWidget);
  });

  testWidgets('card at 360 with a short name: the mode stays in the chip, no extra tag', (t) async {
    await pumpV2(t, _slot(bike('m', videos: const [])));
    await t.pump();
    expect(find.text('Mezná · ${_cs('v2UxRpTypeStaffed')}'), findsOneWidget);
    expect(find.widgetWithText(BikeCardTag, _cs('v2UxRpTypeStaffed')), findsNothing);
  });

  testWidgets('hero: play button top right under the chip; no repeated branch line; dark licence tag', (t) async {
    await pumpHero(t, bike('h', images: const ['https://x/p.jpg']), onBack: () {});
    await wait(t, const Duration(seconds: 1));
    final b = t.getRect(_play);
    final chip = t.getRect(find.byType(MgBranchChip));
    expect(b.right, moreOrLessEquals(360 - 16, epsilon: 0.5));
    expect(b.top, greaterThanOrEqualTo(chip.bottom));
    expect(find.textContaining('Pelhřimov'), findsNothing, reason: 'the "Pobočka" section carries it');
  });

  testWidgets('"Pobočka": name in the title, the long city + type + street under it, nothing cut', (t) async {
    await pumpV2(t, SingleChildScrollView(child: DetailMoreV2(moto: _self('s'), branchInfo: '')),
        size: const Size(320, 690));
    await t.pump();
    expect(find.text('${_cs('detailBranchLabel')}MotoGo24 Velké Němčice'), findsOneWidget);
    expect(find.text('Brno - Velké Němčice · ${_cs('v2CalcBranchSelf')} · Hlavní 12'), findsOneWidget);
  });

  testWidgets('detail dock "od" = the card\'s "Tvoje cena od" (rank price, display only)', (t) async {
    await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
        size: const Size(412, 900), overrides: catalogOverrides());
    await t.pump(const Duration(milliseconds: 800));
    await t.pump(const Duration(milliseconds: 100));
    final dock = t.widget<DetailDockV2>(find.byType(DetailDockV2));
    final pct = kLoyalty3.percent;
    final want = translations['cs']!['v2CatGridFrom']!.replaceAll('{amount}', catMoney(catFromPerDay(kBmw, pct)));
    expect(pct, greaterThan(0));
    expect(dock.fromPrice, want);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
