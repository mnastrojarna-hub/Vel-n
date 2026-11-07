// CB-11 express layout of the v2 booking form: a returning customer whose
// trip is ready sees "Termín a předání" and "Máme to připravené" folded.
// Tests that drive a control inside those sections open them first — the
// way a customer does (tap the row / the card).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/booking/v2/booking_express_v2.dart';

/// Opens every folded express section of the booking form on screen
/// (no-op when there is none or all are open).
Future<void> openBookingExpress(WidgetTester t) async {
  Future<void> tapOpen(Finder f) async {
    await Scrollable.ensureVisible(t.element(f), alignment: 0.4);
    await t.pump();
    await t.tap(f, warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  final row = find.byType(BookingHandoverRowV2);
  if (row.evaluate().isNotEmpty && !t.widget<BookingHandoverRowV2>(row.first).open) {
    await tapOpen(find.descendant(of: row.first, matching: find.byType(MgPress)).first);
  }
  final card = find.byType(BookingReadyCardV2);
  if (card.evaluate().isNotEmpty && !t.widget<BookingReadyCardV2>(card.first).open) {
    await tapOpen(find.descendant(of: card.first, matching: find.byType(MgPress)).first);
  }
}
