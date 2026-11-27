import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/v2/flag/v2_scope.dart';
import '../../../booking/booking_entry.dart' show startBookingFromSelection;
import '../../../booking/booking_models.dart' show BookingDraft;
import '../../../booking/v2/booking_carry_v2.dart' show draftDatesFor, followDraftDates;
import '../../../booking/v2/booking_sync_v2.dart' show bookingRangeBusy;
import '../../../reservations/reservation_provider.dart' show reservationsProvider;
import '../../catalog_provider.dart';
import '../../moto_model.dart';
import '../catalog_date_sheet_v2.dart' show catClearDates, catSetDates;
import '../catalog_mode_sync.dart' show catBeforeToday;

/// Date carry of the bike detail (owner 2026-10-22 „nic nevyplňovat
/// dvakrát“), moved out of `moto_detail_page.dart` (r2, file size): the
/// SAME rules, the page only calls these.

/// Start dates of the detail: v2 — the in-progress booking of THIS bike
/// wins, else the catalog filter; a range that already started in the past
/// (app alive across days) is not carried (the Home funnel's rule). Old
/// look: the filter only, as before.
(DateTime?, DateTime?) detailStartDates(BuildContext context, WidgetRef ref, String motoId) {
  final filter = ref.read(catalogFilterProvider);
  if (!MgV2.peek(context)) return (filter.startDate, filter.endDate);
  var carried = draftDatesFor(ref, motoId);
  if (carried != null && catBeforeToday(carried.$1)) carried = null;
  final s = carried?.$1 ?? filter.startDate, e = carried?.$2 ?? filter.endDate;
  if (s != null && catBeforeToday(s)) return (null, null);
  return (s, e);
}

/// v2: dates changed in the booking form („Změnit“) for this bike → the
/// range the detail under it should show (null = nothing to follow). A
/// start-only pick booked as one day (the draft then ends on its start)
/// stays this detail's own choice — it is not a range for the catalog.
(DateTime, DateTime)? detailFollowDraft(
  BookingDraft? prev,
  BookingDraft next,
  String motoId,
  DateTime? selStart,
  DateTime? selEnd,
) {
  final r = followDraftDates(prev, next, motoId);
  if (r == null || (r.$1 == selStart && r.$2 == selEnd)) return null;
  if (selEnd == null && r.$1 == selStart && r.$2 == selStart) return null;
  return r;
}

/// A range picked in the detail applies to the whole catalog (pager, Motorky
/// list, Home pill) — the same write as picking dates in Motorky.
void detailShareRange(WidgetRef ref, DateTime s, DateTime e) {
  final f = ref.read(catalogFilterProvider);
  if (f.startDate != s || f.endDate != e) catSetDates(ref, s, e);
}

/// A reset in the detail clears the catalog dates too.
void detailShareReset(WidgetRef ref) {
  final f = ref.read(catalogFilterProvider);
  if (f.startDate != null || f.endDate != null) catClearDates(ref);
}

/// v2: the chosen days (a start alone = that day) hit a booked day of this
/// bike — dates carried from the list / Home / the calculator are never
/// checked by the calendar itself. The booking form's rule
/// (`bookingRangeBusy`): the customer's own unpaid draft of this bike (a
/// declined card / cancelled 3DS) does not count — the payment replaces it,
/// as in the old look. Unknown bookings / reservations = not busy.
/// [watch] false = a one-off check from a tap handler (the bike card's
/// "Rezervovat"): the reservations are read, not listened to.
bool detailRangeBusy(
  WidgetRef ref,
  AsyncValue<List<BookedDateRange>> booked,
  String motoId,
  DateTime? s,
  DateTime? e, {
  bool watch = true,
}) =>
    bookingRangeBusy(
      booked: booked.valueOrNull,
      own: (watch ? ref.watch(reservationsProvider) : ref.read(reservationsProvider)).valueOrNull,
      motoId: motoId,
      start: s,
      end: e ?? s,
    );

/// The rule of the detail's primary button (moved out of the page, 5.0.3 —
/// the bike card's "Rezervovat" asks the same): REZERVOVAT only with a start
/// day that is not [busy]; otherwise the date step ("VYBRAT TERMÍN" /
/// "ZMĚNIT TERMÍN").
bool detailCanReserve(DateTime? start, bool busy) => start != null && !busy;

/// REZERVOVAT of the bike detail (PM-3; the body of the page's `_reserve`,
/// shared with the bike card since 5.0.3): the chosen days — a start alone =
/// that single day — go to `startBookingFromSelection`.
void detailReserve(BuildContext ctx, WidgetRef ref, Motorcycle moto, DateTime start, DateTime? end) =>
    startBookingFromSelection(ctx, ref, moto, start, end ?? start);
