// Journey rig smoke test (always on): the rig boots the real router in
// state `ready` and shows Home with the v2 nav; one real tap on a tab.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';

import 'journey_rig.dart';
import 'journey_states.dart';
import 'journey_steps.dart';

void main() {
  testWidgets('journey rig boots in state ready and shows Home', (tester) async {
    final rig = await JourneyRig.boot(tester, JourneyState.ready);
    expect(rig.location, '/');
    expect(find.byType(HomeScreenV2), findsOneWidget);
    expect(find.byType(V2NavBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The tab is reachable by a real tap; the probe names what it hit.
    final c = tester.getCenter(find.text('Rezervace').hitTestable().first);
    expect(probe(tester, c), startsWith('HIT'));
    await tester.tapAt(c);
    await rig.settle();
    expect(rig.location, '/reservations');
    expect(probe(tester, const Offset(180, 300)), isA<String>());
    await rig.dispose();
  });
}
