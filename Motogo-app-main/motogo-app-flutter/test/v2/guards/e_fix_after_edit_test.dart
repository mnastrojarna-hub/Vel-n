// Accepted clarity fixes, part "after" (úloha E, 2026-11-13), on the REAL
// edit screen (journey rig: real router, real edit State, fake backend):
// E3-02 a refund without a date change is told before saving and the
// result is not called a shortening; E3-06 the shorten dock button; E3-04
// the licence filter still hides the BMW (A) for an A2 customer and the
// list says so; E3-10 the old look keeps its long hint.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';

import '../journey/journey_backend.dart' show journeyRequests;
import '../journey/journey_rig.dart';
import '../journey/journey_states.dart';

String _t(String key) => translations['cs']?[key] ?? key;
const _edit = '/reservations/e1aaaaaaa-1111-2222-3333-444455556666/edit';

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + offset);
}

Future<void> _tapText(JourneyRig rig, String text) async {
  final t = rig.tester;
  var f = find.text(text, findRichText: true).hitTestable();
  if (f.evaluate().isEmpty) f = find.textContaining(text, findRichText: true).hitTestable();
  expect(f, findsWidgets, reason: 'no visible "$text"');
  final c = t.getCenter(f.first);
  await rig.guard(() => t.tapAt(c));
  await rig.settle();
}

/// As the journey scripts' {"wait":3000},{"wait":15000} after a save.
Future<void> _waitSave(JourneyRig rig) async {
  for (final ms in [300, 3000, 15000]) {
    await rig.guard(() => rig.tester.pump(Duration(milliseconds: ms)));
    await rig.settle();
  }
}

Future<void> _scroll(JourneyRig rig, double dy) async {
  await rig.tester.dragFrom(const Offset(180, 560), Offset(0, -dy));
  await rig.settle();
}

Finder _dock(String text) => find.textContaining(text).hitTestable();

void main() {
  testWidgets('E3-02 later pickup time with the late-pickup discount', (t) async {
    final rig = await JourneyRig.boot(t, JourneyState.paidUpcomingExtFree, start: _edit);
    // Nothing changed yet: the extend tab keeps "ULOŽIT ZMĚNY".
    expect(_dock(_t('saveChangesBtn')), findsOneWidget);
    await _scroll(rig, 450);
    await _tapText(rig, '09:00');
    await _tapText(rig, '15:00');
    // Before saving: the refund is announced in the dock.
    expect(_dock('Vrátíme ti'), findsOneWidget);
    expect(_dock(_t('saveChangesBtn')), findsOneWidget);
    await _tapText(rig, _t('saveChangesBtn'));
    await _waitSave(rig);
    expect(find.text(_t('jxChangeSavedTitle')), findsOneWidget);
    expect(find.textContaining(_t('jxChangeSavedLead')), findsOneWidget);
    expect(find.text(_t('shorteningConfirmed')), findsNothing);
    expect(find.textContaining(_t('reservationShortened')), findsNothing);
    await rig.dispose();
  });

  testWidgets('E3-06 / E3-02 a real shortening: own button, still "Zkrácení potvrzeno"', (t) async {
    final rig = await JourneyRig.boot(t, JourneyState.paidUpcomingExtFree, start: _edit);
    await _tapText(rig, 'Zkrátit');
    await _tapText(rig, 'Zkrátit konec');
    // New last day: one day after the start (or the start, at a month edge).
    final s = _day(3), n = _day(4);
    final d = n.month == s.month ? n : s;
    final cell = find.bySemanticsLabel(RegExp(' ${d.day}\\. ${d.month}\\. ${d.year}'));
    await t.ensureVisible(cell.first);
    await rig.settle();
    final c = t.getCenter(cell.first);
    await rig.guard(() => t.tapAt(c));
    await rig.settle();
    expect(_dock(_t('jxShortenCta')), findsOneWidget);
    expect(_dock(_t('saveChangesBtn')), findsNothing);
    expect(_dock('Vrátíme ti'), findsOneWidget);
    final before = journeyRequests.length;
    await _tapText(rig, _t('jxShortenCta'));
    await _waitSave(rig);
    // One tap = one save of the booking (no extra step, no double save).
    final saves = journeyRequests.sublist(before).where((r) => r == 'PATCH /rest/v1/bookings').length;
    expect(saves, 1);
    expect(find.text(_t('shorteningConfirmed')), findsOneWidget);
    await rig.dispose();
  });

  testWidgets('E3-04 swap list: BMW (A) hidden for A2, the list says why', (t) async {
    final rig = await JourneyRig.boot(t, JourneyState.paidUpcomingSwap,
        start: '/reservations/w1aaaaaaa-1111-2222-3333-444455556666/edit');
    await _tapText(rig, 'Výměna');
    await _scroll(rig, 300);
    expect(find.textContaining('Yamaha'), findsWidgets);
    expect(find.textContaining('BMW'), findsNothing);
    expect(find.text(_t('jxLicenceHiddenNote')), findsOneWidget);
    await rig.dispose();
  });

  testWidgets('E3-04 whole-term change list: BMW (A) hidden for A2, the list says why', (t) async {
    final rig = await JourneyRig.boot(t, JourneyState.paidUpcomingSwap,
        start: '/reservations/w1aaaaaaa-1111-2222-3333-444455556666/edit');
    final head = find.text(_t('motoChange'));
    await t.scrollUntilVisible(head, 300, scrollable: find.byType(Scrollable).first);
    await rig.settle();
    await _tapText(rig, _t('motoChange'));
    final note = find.text(_t('jxLicenceHiddenNote'));
    await t.scrollUntilVisible(note, 200, scrollable: find.byType(Scrollable).first);
    expect(note, findsOneWidget);
    expect(find.textContaining('Yamaha'), findsWidgets);
    expect(find.textContaining('BMW'), findsNothing);
    await rig.dispose();
  });

  testWidgets('E3-10 old look keeps the long self-service hint', (t) async {
    final rig = await JourneyRig.boot(t, JourneyState.paidUpcomingExtFree, start: _edit, v2: false);
    final hint = find.textContaining(_t('ssPickupHint'));
    await t.scrollUntilVisible(hint, 300, scrollable: find.byType(Scrollable).first);
    expect(hint, findsOneWidget);
    expect(find.text(_t('jxLateHead')), findsNothing);
    await rig.dispose();
  });
}
