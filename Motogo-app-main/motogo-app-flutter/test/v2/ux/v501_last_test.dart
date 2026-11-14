// 5.0.1 last repair (second re-check): the Home offer follows the panel
// filters and says so, the loud filter card shows every chip, Motorky's
// calendar marks closed days, "Volná od" without dates, a stalled next
// hero video goes back to the photo, hyphenated names stay whole.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/bike_free_label_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_hero_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/video_chrome_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_filter_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_filter_chips_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_closed_days_v2.dart';
import 'package:motogo_app/features/home/v2/funnel_carousel_v2.dart' show homeNoOrphan;
import 'package:motogo_app/features/home/v2/home_funnel_parts.dart';
import 'package:motogo_app/features/home/v2/home_offer_provider.dart';

import '../support/fakes_home.dart';
import '../support/v2_harness.dart';
import 'v501_media_fake.dart';

String _cs(String key) => translations['cs']![key]!;
const _tr = AppTranslations('cs');

DateTime _d(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + n);
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerHomeStrings();
  });

  test('closed days: only days on which EVERY branch is closed; a set branch counts alone', () {
    const a = Motorcycle(id: 'a', model: 'A', branchId: 'b1');
    const b = Motorcycle(id: 'b', model: 'B', branchId: 'b2');
    final closures = [HomeClosure('b1', _d(0), _d(10)), HomeClosure('b2', _d(5), _d(20))];
    final r = motorkyClosedDays(const [a, b], closures);
    expect(r, hasLength(1));
    expect([r.single.start, r.single.end], [_d(5), _d(10)]);
    expect(r.single.status, 'branch_closed');
    final only = motorkyClosedDays(const [a, b], closures, branch: 'b2');
    expect([only.single.start, only.single.end], [_d(5), _d(20)]);
    expect(motorkyClosedDays(const [a, b], const []), isEmpty, reason: 'no closures (or a failed read) = no change');
  });

  test('"Volná dnes" / "Volná od" without dates', () {
    const today = Motorcycle(id: 't', model: 'T', availableToday: true);
    const busy = Motorcycle(id: 'x', model: 'X', availableToday: false);
    expect(bikeFreeLabel(_tr, today, const {}), (_cs('v2CatFreeToday'), true));
    final (text, now) = bikeFreeLabel(_tr, busy, {'x': _d(5)});
    expect(now, isFalse);
    expect(text, isNotNull);
    expect(text, startsWith(_cs('homeOfferFreeFrom').split('{').first));
    expect(bikeFreeLabel(_tr, busy, const {}).$1, isNull, reason: 'unknown next day: no pill');
  });

  test('hyphenated model names do not break at the hyphen', () {
    expect(homeNoOrphan('Suzuki DL 650 V-strom'), 'Suzuki DL 650 V-⁠strom');
    expect(homeNoOrphan('Benelli TRK 502 X'), 'Benelli TRK 502 X');
  });

  test('Home offer follows the panel filters (display only); none matching = all bikes', () async {
    Future<HomeOffer> offer(CatalogFilter f) async {
      final c = ProviderContainer(overrides: [
        ...homeOverrides(),
        catalogFilterProvider.overrideWith((ref) => f),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(homeOfferProvider, (_, __) {});
      await c.read(motorcyclesProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return sub.read();
    }

    final all = await offer(const CatalogFilter());
    expect(all.filters, 0);
    expect(all.bikes.length, greaterThan(1));
    final cat = all.bikes.first.category!;
    final f = CatalogFilter(category: cat);
    final narrowed = await offer(f);
    expect(narrowed.filters, 1);
    expect(narrowed.bikes, isNotEmpty);
    expect(narrowed.bikes.every((m) => m.category == cat), isTrue);
    final none = await offer(const CatalogFilter(category: 'no-such-category'));
    expect(none.filters, 0, reason: 'nothing passes: all bikes, no "filters on" pill');
    expect(none.bikes.length, all.bikes.length);
  });

  testWidgets('offer pill "Filtry zapnuté (n)" opens the filter card; narrow = icon + n; no bare eyebrow icon',
      (t) async {
    var opened = 0;
    Widget row(int filters) => Padding(
          padding: const EdgeInsets.all(16),
          child: FunnelTopRow(count: 4, index: 0, onNext: () {}, filters: filters, onFilters: () => opened++),
        );
    await pumpV2(t, row(2));
    await t.pump();
    expect(find.text(_cs('motoFltOn').replaceAll('{n}', '2').toUpperCase()), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('funnel-filters-on')));
    expect(opened, 1);
    await pumpV2(t, row(2), size: const Size(240, 640));
    await t.pump();
    expect(find.text('2'), findsOneWidget, reason: 'compact: the filter icon + the count');
    await pumpV2(t, row(0), size: const Size(240, 640));
    await t.pump();
    expect(find.bySemanticsLabel(_cs('v2HomeFnEyebrow')), findsNothing, reason: 'too narrow: no icon-only pill');
  });

  testWidgets('loud filter card at 320: every chip and its ✕ visible and working', (t) async {
    final dropped = <String>[];
    final chips = [
      MotoFilterChipItem('ŘP A2', () => dropped.add('lic')),
      MotoFilterChipItem('Výkon 30–60 kW', () => dropped.add('kw')),
    ];
    await pumpV2(
      t,
      SingleChildScrollView(
        child: MotoFilterCardV2(
            open: false, active: 2, onToggle: () {}, onReset: () {}, body: const SizedBox(), chips: chips),
      ),
      size: const Size(320, 640),
    );
    await t.pump();
    for (final c in chips) {
      final x = find.byKey(ValueKey('moto-filter-x-${c.label}'));
      final r = t.getRect(x);
      expect(r.right, lessThanOrEqualTo(320), reason: '${c.label}: ✕ inside the screen');
      await t.tap(x);
    }
    expect(dropped, ['lic', 'kw']);
    expect(find.byKey(const ValueKey('moto-filter-clear')), findsOneWidget);
  });

  testWidgets('hero: a next video that never starts goes back to the photo (no frozen frame)', (t) async {
    final fake = FakeVideos.install(wifi: true);
    addTearDown(fake.uninstall);
    final pc = PageController();
    addTearDown(pc.dispose);
    final m = bike('h', videos: const ['https://x/1.mp4', 'https://x/2.mp4'], images: const ['https://x/p.jpg']);
    await pumpV2(
      t,
      SingleChildScrollView(
        child: Column(children: [
          DetailHeroV2(
            moto: m,
            images: m.images,
            branchInfo: '',
            imageIndex: 0,
            pageCtrl: pc,
            onImageChanged: (_) {},
            onOpenGallery: () {},
            onBack: null,
            height: 468,
          ),
          const SizedBox(height: 1200),
        ]),
      ),
    );
    await wait(t, const Duration(seconds: 6));
    final first = fake.created.single;
    expect(first.playing, isTrue);
    fake.stalling = true;
    first.finish();
    await wait(t, const Duration(seconds: 2));
    expect(find.byType(VideoMuteDiscV2), findsOneWidget, reason: 'still handing over');
    await wait(t, const Duration(seconds: 8));
    expect(find.byType(VideoMuteDiscV2), findsNothing, reason: 'back to the photo');
    expect(fake.alive, 0, reason: 'both players disposed');
    await t.pumpWidget(const SizedBox());
  });
}
