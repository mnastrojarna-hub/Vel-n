// 5.0.1 "fotka, pak video" (owner: the photo first, after ~5 s of looking
// the video, only on Wi-Fi; on mobile data / reduced motion the photo stays
// with a play button; never two players) + the branch chip on the photo.
// A fake player only — no network.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/widgets/mg_branch_chip.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';

import '../support/v2_harness.dart';
import 'v501_media_fake.dart';

const _price = CatCardPrice(label: 'Cena od', value: '2 727 Kč', unit: '/den', sub: '', grid: '');

Widget card(Motorcycle m, {double h = 780}) => MotoCardFullV2(
      key: ValueKey('card-${m.id}'),
      moto: m,
      price: _price,
      availability: 'Dnes volná',
      ctaLabel: 'Detail',
      onOpen: () {},
      height: h,
    );

Future<ScrollController> pumpList(WidgetTester t, List<Motorcycle> motos, {bool reduced = false}) async {
  final sc = ScrollController();
  addTearDown(sc.dispose);
  await pumpV2(
    t,
    ListView(controller: sc, children: [for (final m in motos) card(m)]),
    reducedMotion: reduced,
  );
  return sc;
}

double layerOpacity(WidgetTester t, {int at = 0}) =>
    t.widget<AnimatedOpacity>(find.byKey(const ValueKey('bike-video-layer')).at(at)).opacity;

void main() {
  setUpAll(loadMontserrat);
  late FakeVideos fake;
  setUp(() => fake = FakeVideos.install(wifi: true));
  tearDown(() => fake.uninstall());

  testWidgets('Wi-Fi: photo first, loads after ~1 s, cross-fades to the looped muted video after ~5 s', (t) async {
    await pumpList(t, [bike('a')]);
    await wait(t, const Duration(milliseconds: 900));
    expect(fake.created, isEmpty, reason: 'no download in the first second');
    await wait(t, const Duration(milliseconds: 700));
    expect(fake.created, hasLength(1), reason: 'loading in the background while the photo shows');
    expect(fake.created.single.playing, isFalse);
    expect(layerOpacity(t), 0);
    await wait(t, const Duration(seconds: 4));
    final p = fake.created.single;
    expect(p.playing, isTrue);
    expect(p.volume, 0, reason: 'muted');
    expect(p.looping, isTrue, reason: 'the list card loops its first video');
    expect(p.url, 'https://x/v1.mp4');
    await wait(t, const Duration(milliseconds: 600));
    expect(layerOpacity(t), 1);
    expect(find.byKey(const ValueKey('fake-video-https://x/v1.mp4')), findsOneWidget);
    expect(find.byKey(const ValueKey('bike-video-play')), findsNothing);
    expect(fake.maxAlive, 1);
  });

  testWidgets('mobile data: the photo stays, no download; the play button starts the video', (t) async {
    fake.wifi = false;
    await pumpList(t, [bike('a')]);
    await wait(t, const Duration(seconds: 7));
    expect(fake.created, isEmpty);
    expect(layerOpacity(t), 0);
    final play = find.byKey(const ValueKey('bike-video-play'));
    expect(play, findsOneWidget);
    expect(find.text('Pustit video'), findsOneWidget);
    await t.tap(play);
    await wait(t, const Duration(seconds: 1));
    expect(fake.created, hasLength(1));
    expect(fake.created.single.playing, isTrue);
    expect(layerOpacity(t), 1);
    expect(play, findsNothing);
  });

  testWidgets('reduced motion: no autoplay, no download; the play button is there', (t) async {
    await pumpList(t, [bike('a')], reduced: true);
    await wait(t, const Duration(seconds: 7));
    expect(fake.created, isEmpty);
    expect(find.byKey(const ValueKey('bike-video-play')), findsOneWidget);
  });

  testWidgets('no video: nothing loads, no play button, no layer', (t) async {
    await pumpList(t, [bike('a', videos: const [])]);
    await wait(t, const Duration(seconds: 7));
    expect(fake.created, isEmpty);
    expect(find.byKey(const ValueKey('bike-video-play')), findsNothing);
    expect(find.byKey(const ValueKey('bike-video-layer')), findsNothing);
  });

  testWidgets('scroll on: the player is disposed at once; the next bike plays; never two players', (t) async {
    final sc = await pumpList(t, [bike('a'), bike('b', videos: const ['https://x/b.mp4'])]);
    await wait(t, const Duration(seconds: 6));
    expect(fake.created.single.playing, isTrue);
    sc.jumpTo(300);
    await t.pump();
    await t.pump();
    expect(fake.created.single.disposed, isTrue, reason: 'scrolled away');
    expect(fake.alive, 0);
    // A short scroll (both cards partly on screen): nothing starts.
    await wait(t, const Duration(seconds: 6));
    expect(fake.created, hasLength(1));
    sc.jumpTo(780);
    await wait(t, const Duration(seconds: 6));
    expect(fake.created, hasLength(2));
    expect(fake.created.last.url, 'https://x/b.mp4');
    expect(fake.created.last.playing, isTrue);
    expect(fake.maxAlive, 1);
  });

  testWidgets('a scroll during the countdown restarts it (settled 5 s)', (t) async {
    final sc = await pumpList(t, [bike('a'), bike('b')]);
    await wait(t, const Duration(seconds: 3));
    sc.jumpTo(2);
    await wait(t, const Duration(seconds: 3));
    expect(fake.created.single.playing, isFalse, reason: 'only 3 s since the last scroll');
    await wait(t, const Duration(seconds: 3));
    expect(fake.created.single.playing, isTrue);
  });

  testWidgets('app in the background stops and disposes; back in front plays again after the wait', (t) async {
    await pumpList(t, [bike('a')]);
    await wait(t, const Duration(seconds: 6));
    expect(fake.alive, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(fake.alive, 0);
    expect(layerOpacity(t), 0);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await wait(t, const Duration(seconds: 2));
    expect(fake.created.last.playing, isFalse);
    await wait(t, const Duration(seconds: 5));
    expect(fake.created.last.playing, isTrue);
    expect(fake.alive, 1);
  });

  testWidgets('another page on top stops and disposes the video', (t) async {
    await pumpList(t, [bike('a')]);
    await wait(t, const Duration(seconds: 6));
    expect(fake.alive, 1);
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('detail'))));
    await wait(t, const Duration(seconds: 1));
    expect(fake.alive, 0);
    await wait(t, const Duration(seconds: 7));
    expect(fake.alive, 0, reason: 'covered: never restarts');
    nav.pop();
    await wait(t, const Duration(seconds: 7));
    expect(fake.alive, 1);
    expect(fake.created.last.playing, isTrue);
  });

  testWidgets('a failing video stays on the photo silently (no layer, no button, no error)', (t) async {
    fake.failing = true;
    await pumpList(t, [bike('a')]);
    await wait(t, const Duration(seconds: 7));
    expect(fake.created, hasLength(1));
    expect(fake.alive, 0);
    expect(layerOpacity(t), 0);
    expect(find.byKey(const ValueKey('bike-video-play')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a photo swipe goes back to the photos; the play button brings the video back', (t) async {
    await pumpList(t, [bike('a', images: const ['https://x/1.jpg', 'https://x/2.jpg'])]);
    await wait(t, const Duration(seconds: 6));
    expect(layerOpacity(t), 1);
    await t.drag(find.byType(PageView), const Offset(-200, 0));
    await wait(t, const Duration(seconds: 1));
    expect(fake.alive, 0);
    expect(layerOpacity(t), 0);
    await wait(t, const Duration(seconds: 6));
    expect(fake.alive, 0, reason: 'browsing photos: no autoplay');
    await t.tap(find.byKey(const ValueKey('bike-video-play')));
    await wait(t, const Duration(seconds: 1));
    expect(fake.alive, 1);
    expect(layerOpacity(t), 1);
  });

  testWidgets('one player in the app: a second stage on screen takes it over', (t) async {
    await pumpV2(
      t,
      Column(children: [
        SizedBox(height: 390, child: card(bike('a'), h: 390)),
        SizedBox(height: 390, child: card(bike('b', videos: const ['https://x/b.mp4']), h: 390)),
      ]),
      size: const Size(360, 780),
    );
    await wait(t, const Duration(seconds: 8));
    expect(fake.created.length, greaterThanOrEqualTo(1));
    expect(fake.alive, 1);
    expect(fake.maxAlive, 1);
  });

  testWidgets('branch chip in the top-right corner of the card photo; no branch line under the category', (t) async {
    await pumpList(t, [bike('a', videos: const [])]);
    await t.pump();
    final chip = find.byType(MgBranchChip);
    expect(chip, findsOneWidget);
    final r = t.getRect(chip);
    expect(r.right, moreOrLessEquals(360 - 12, epsilon: 0.5));
    expect(r.top, lessThan(80));
    final pill = t.getRect(find.text('Dnes volná'));
    expect(r.left, greaterThan(pill.right), reason: 'clear of the availability pill');
    final label = translations['cs']!['v2UxRpTypeStaffed']!;
    expect(find.textContaining('Mezná'), findsOneWidget, reason: 'only the chip names the branch');
    expect(find.text('Mezná · $label'), findsOneWidget);
  });
}
