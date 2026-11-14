// verify:render cases — v5.0.1 photo → video on the full-screen bike card
// and the detail hero (fake player: a 16:9 blue frame), and the branch chip
// in the photo's top-right corner. The harness runs with reduced motion, so
// the photo shows the "Pustit video" button; the "playing" states tap it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_hero_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';

import '../ux/v501_media_fake.dart';
import 'render_harness.dart';

const _price = CatCardPrice(label: 'Cena od', value: '2 727 Kč', unit: '/den', sub: 'průměrně 2 727 Kč za den', grid: '');

const _bike = Motorcycle(
  id: 'r1',
  model: 'BMW R 1200 GS Adventure',
  category: 'cestovni',
  licenseGroups: ['A'],
  powerKw: 92,
  videos: ['https://x/1.mp4', 'https://x/2.mp4'],
  branchName: 'MotoGo24 Mezná',
  branchCity: 'Pelhřimov',
  branchType: 'obslužná',
);

const _self = Motorcycle(
  id: 'r2',
  model: 'Husqvarna 701 Supermoto',
  category: 'supermoto',
  licenseGroups: ['A2', 'A'],
  powerKw: 55,
  videos: ['https://x/3.mp4'],
  branchName: 'MotoGo24 Velké Němčice',
  branchCity: 'Velké Němčice',
  branchType: 'samoobslužná',
);

Widget _card(Motorcycle m) {
  FakeVideos.install(wifi: false);
  return LayoutBuilder(
    builder: (context, c) => MotoCardFullV2(
      moto: m,
      price: _price,
      availability: 'Volná v termínu',
      ctaLabel: 'Detail',
      onOpen: () {},
      height: c.maxHeight,
    ),
  );
}

final _pc = PageController();

Widget _hero(Motorcycle m, {bool pager = true}) {
  FakeVideos.install(wifi: false);
  return Builder(
    builder: (context) => SingleChildScrollView(
      child: Column(children: [
        DetailHeroV2(
          moto: m,
          images: const [],
          branchInfo: '',
          imageIndex: 0,
          pageCtrl: _pc,
          onImageChanged: (_) {},
          onOpenGallery: () {},
          onBack: pager ? null : () {},
          height: (MediaQuery.sizeOf(context).height * 0.6).clamp(340.0, 560.0),
        ),
        const SizedBox(height: 400),
      ]),
    ),
  );
}

Future<void> _tapPlay(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('bike-video-play')));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<RenderCase> v501MediaCases() => [
      RenderCase('v501', 'media', 'card_photo', () => _card(_bike), () => const []),
      RenderCase('v501', 'media', 'card_video', () => _card(_bike), () => const [], after: _tapPlay),
      RenderCase('v501', 'media', 'card_self', () => _card(_self), () => const []),
      RenderCase('v501', 'media', 'hero_photo', () => _hero(_bike), () => const []),
      RenderCase('v501', 'media', 'hero_video', () => _hero(_bike), () => const [], after: _tapPlay),
      RenderCase('v501', 'media', 'hero_back', () => _hero(_self, pager: false), () => const []),
    ];
