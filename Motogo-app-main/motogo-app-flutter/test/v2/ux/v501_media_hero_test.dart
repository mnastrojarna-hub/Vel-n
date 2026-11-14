// 5.0.1: the detail hero plays the bike's videos in order (photo first,
// mute disc + "n / m"), the separate "Video" section is gone from the
// new-look detail, and the branch chip sits in the hero's top-right corner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/widgets/mg_branch_chip.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_hero_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_more_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/video_chrome_v2.dart';
import 'package:motogo_app/features/catalog/widgets/moto_video_player.dart';

import '../support/v2_harness.dart';
import 'v501_media_fake.dart';

Future<void> pumpHero(WidgetTester t, Motorcycle m, {VoidCallback? onBack}) async {
  final pc = PageController();
  addTearDown(pc.dispose);
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
        onBack: onBack,
          height: 468,
        ),
        const SizedBox(height: 1200),
      ]),
    ),
  );
}

void main() {
  setUpAll(loadMontserrat);
  late FakeVideos fake;
  setUp(() => fake = FakeVideos.install(wifi: true));
  tearDown(() => fake.uninstall());

  testWidgets('hero: photo, then the videos in their order with "n / m" and the mute disc', (t) async {
    await pumpHero(t, bike('h', videos: const ['https://x/1.mp4', 'https://x/2.mp4'], images: const ['https://x/p.jpg']));
    await wait(t, const Duration(seconds: 3));
    expect(find.byType(VideoMuteDiscV2), findsNothing, reason: 'photo first');
    expect(find.text('1 / 1'), findsOneWidget, reason: 'the photo counter while the photo shows');
    await wait(t, const Duration(seconds: 3));
    final first = fake.created.single;
    expect(first.url, 'https://x/1.mp4');
    expect(first.playing, isTrue);
    expect(first.looping, isFalse, reason: 'several videos play one after another');
    expect(find.byType(VideoMuteDiscV2), findsOneWidget);
    expect(find.byType(VideoCountPillV2), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    // Unmute.
    await t.tap(find.byType(VideoMuteDiscV2));
    await t.pump();
    expect(first.volume, 1);
    first.finish();
    await wait(t, const Duration(seconds: 1));
    expect(first.disposed, isTrue);
    final second = fake.created.last;
    expect(second.url, 'https://x/2.mp4');
    expect(second.playing, isTrue);
    expect(second.volume, 1, reason: 'the mute choice carries over');
    expect(find.text('2 / 2'), findsOneWidget);
    expect(fake.maxAlive, 1);
    second.finish();
    await wait(t, const Duration(seconds: 1));
    expect(fake.created.last.url, 'https://x/1.mp4', reason: 'after the last one the first again');
    expect(fake.maxAlive, 1);
  });

  testWidgets('hero: one video loops; mobile data keeps the photo with the play button', (t) async {
    fake.wifi = false;
    await pumpHero(t, bike('h'));
    await wait(t, const Duration(seconds: 7));
    expect(fake.created, isEmpty);
    await t.tap(find.byKey(const ValueKey('bike-video-play')));
    await wait(t, const Duration(seconds: 1));
    expect(fake.created.single.looping, isTrue);
    expect(find.byType(VideoCountPillV2), findsNothing, reason: 'no "n / m" with one video');
    expect(find.byType(VideoMuteDiscV2), findsOneWidget);
  });

  testWidgets('hero scrolled away stops the video', (t) async {
    await pumpHero(t, bike('h'));
    await wait(t, const Duration(seconds: 6));
    expect(fake.alive, 1);
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(400);
    await t.pump();
    await t.pump();
    expect(fake.alive, 0);
    await wait(t, const Duration(seconds: 7));
    expect(fake.alive, 0, reason: 'only 68 of 468 px on screen');
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await wait(t, const Duration(seconds: 6));
    expect(fake.alive, 1);
    expect(fake.created.last.playing, isTrue);
  });

  testWidgets('hero: branch chip top right, level with the back control, clear of it', (t) async {
    await pumpHero(t, bike('h', videos: const []), onBack: () {});
    await t.pump();
    final chip = t.getRect(find.byType(MgBranchChip));
    expect(chip.right, moreOrLessEquals(360 - 16, epsilon: 0.5));
    expect(chip.left, greaterThan(16 + 44 + 8));
    expect(chip.top, lessThan(60));
    final staffed = translations['cs']!['v2UxRpTypeStaffed']!;
    expect(find.text('Mezná · $staffed'), findsOneWidget);
  });

  testWidgets('new-look detail: no separate "Video" section, no second player; Pobočka stays', (t) async {
    await pumpV2(t, SingleChildScrollView(child: DetailMoreV2(moto: bike('h'), branchInfo: '')));
    await t.pump();
    expect(find.byType(MotoVideoPlayer), findsNothing);
    expect(find.text(translations['cs']!['v2DetVideo']!), findsNothing);
    expect(find.byKey(const ValueKey('det-branch')), findsOneWidget);
    expect(fake.created, isEmpty);
  });
}
