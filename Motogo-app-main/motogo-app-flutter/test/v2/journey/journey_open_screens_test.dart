// The booking-edit page and the profile page open under the REAL router and
// shell in BOTH looks (flag on = new look, flag off = old look) and show the
// same data. Guards the 2026-11-13 fix: both screens used to call
// `ref.invalidate` in initState, which in debug builds threw
// "dependOnInheritedWidgetOfExactType … before initState() completed" and
// replaced the page with the error widget; the fresh load now starts in the
// first didChangeDependencies (same synchronous step, before the first build).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/profile/profile_screen.dart';
import 'package:motogo_app/features/reservations/reservation_edit_screen.dart';

import 'journey_rig.dart';
import 'journey_states.dart';

Future<void> _tapText(JourneyRig rig, String text) async {
  await rig.tester.tapAt(rig.tester.getCenter(find.text(text).hitTestable().first));
  await rig.settle();
}

void main() {
  for (final v2 in [true, false]) {
    final look = v2 ? 'new look' : 'old look';

    testWidgets('edit page loads from the booking card ($look)', (tester) async {
      final rig = await JourneyRig.boot(tester, JourneyState.paidUpcomingExtFree, v2: v2);
      rig.router.go('/reservations');
      await rig.settle();
      // The card's edit button ("Upravit" / "✏️ Upravit" in the old look).
      final edit = find.textContaining('Upravit').hitTestable().first;
      await tester.tapAt(tester.getCenter(edit));
      await rig.settle();
      expect(tester.takeException(), isNull);
      expect(rig.location, contains('/reservations/e1aaaaaaa-1111-2222-3333-444455556666/edit'));
      expect(find.byType(ReservationEditScreen), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      // Same content in both looks: title, bike + booking number, the
      // extend tab and the calendar of the booking's month.
      expect(find.text('Upravit rezervaci'), findsWidgets);
      expect(find.textContaining('Husqvarna 701 SM'), findsWidgets);
      expect(find.textContaining('#55556666'), findsWidgets);
      expect(find.textContaining('Prodloužit'), findsWidgets);
      expect(find.textContaining('VYZVEDNUTÍ'), findsWidgets);
      // The month of the booking (it starts in 3 days).
      final start = DateTime.now().add(const Duration(days: 3));
      const months = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září',
        'Říjen', 'Listopad', 'Prosinec'];
      expect(find.textContaining('${months[start.month - 1]} ${start.year}'), findsWidgets);
      await rig.dispose();
    });

    testWidgets('profile page loads ($look)', (tester) async {
      final rig = await JourneyRig.boot(tester, JourneyState.paidUpcoming, v2: v2);
      if (v2) {
        await _tapText(rig, 'Profil'); // nav tab
      } else {
        rig.router.go('/profile'); // the old nav has no profile tab
        await rig.settle();
      }
      expect(tester.takeException(), isNull);
      expect(rig.location, '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      // Same data in both looks: name and the personal-data block.
      expect(find.textContaining('Jan Novák'), findsWidgets);
      expect(find.textContaining('Osobní údaje'), findsWidgets);
      // Only the known debug-only listener assertion may have been seen
      // (rig.guard); anything else would have failed the test.
      expect(rig.debugAsserts.every((a) => a.startsWith('markNeedsBuild during build')), isTrue);
      await rig.dispose();
    });
  }
}
