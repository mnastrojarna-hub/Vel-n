// 5.0.3 (owner 2026-11-27: "V trasách je navíc můj rank … rank přece vidím
// v profilu a když kliknu na odznak"): the "Moje zážitky" summary of
// Trasy → Moje has no rank row — the count tiles are followed by
// "Vytvořit novou trasu" — whatever the loyalty status is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_summary_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_tabs_v2.dart';

import '../screens/rides_cases.dart';
import '../support/fakes_rides.dart';
import '../support/v2_harness.dart';

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRidesStrings();
    ridesMockPathProvider();
  });

  testWidgets('Trasy → Moje: the summary shows no rank (name, level line, emblem) with a loaded rank', (tester) async {
    await pumpV2(tester, mojeView(), size: const Size(360, 2400), overrides: ridesOverrides(), scaffold: false);
    await tester.pump(const Duration(milliseconds: 600));
    final card = find.byType(MojeSummaryV2);
    expect(card, findsOneWidget);
    // kLoyaltyRides = "Motorkář", level 3 — loaded, and still not in the card.
    expect(find.descendant(of: card, matching: find.text(kLoyaltyRides.rankName)), findsNothing);
    expect(find.descendant(of: card, matching: find.textContaining('Level')), findsNothing);
    expect(find.descendant(of: card, matching: find.textContaining('sleva')), findsNothing);
    // (The hub header's logo ring — the badge the owner taps — keeps it.)
    expect(find.descendant(of: card, matching: find.bySemanticsLabel(RegExp(kLoyaltyRides.rankName))), findsNothing);
    // What stays: the three count tiles and the create button.
    for (final label in ['Objevená místa', 'Vytvořit novou trasu']) {
      expect(find.descendant(of: card, matching: find.textContaining(RegExp(label, caseSensitive: false))), findsWidgets);
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await ridesEnd(tester);
  });

  for (final size in const [Size(360, 780), Size(320, 640)]) {
    testWidgets('summary ${size.width.toInt()}: the count tiles are followed by the create button (14 px), taps intact',
        (tester) async {
      final log = <String>[];
      await pumpV2(
        tester,
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MojeSummaryV2(
            loggedIn: true,
            rides: kRides,
            savedCount: 2,
            placesCount: 5,
            onSub: (s) => log.add('sub:${s.name}'),
            onCreateRoute: () => log.add('create'),
            onLogin: () => log.add('login'),
          ),
        ),
        size: size,
        overrides: ridesOverrides(),
        reducedMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final button = find.byType(MgBtnInk);
      expect(button, findsOneWidget);
      final tiles = find.ancestor(of: find.textContaining('Objevená'), matching: find.byType(MgPress));
      expect(tiles, findsWidgets);
      final gap = tester.getRect(button).top - tester.getRect(tiles.first).bottom;
      expect(gap, moreOrLessEquals(14, epsilon: 0.5), reason: 'nothing between the tiles and the button');
      await tester.tap(tiles.first);
      await tester.tap(button);
      expect(log, ['sub:${MojeSub.places.name}', 'create']);
      expect(tester.takeException(), isNull);
    });
  }
}
