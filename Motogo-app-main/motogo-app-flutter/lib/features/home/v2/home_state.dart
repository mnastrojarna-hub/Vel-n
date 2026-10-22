import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/pending_sos_fab_provider.dart';
import '../../reservations/reservation_models.dart';

/// What the Home ticket shows (PLAN §2.1, DESIGN_V2 §5.3). Only derived from
/// data the app already has — no new fetches.
enum HomeTicket {
  /// No upcoming / active booking → booking funnel.
  s0,

  /// SOS replacement not chosen yet.
  s1,

  /// Unpaid pending booking (or its payment being verified).
  s2,

  /// Upcoming paid booking, documents missing.
  s3,

  /// Upcoming, staffed branch pickup.
  s4,

  /// Upcoming, delivery to an address.
  s5,

  /// Upcoming, self-service branch, documents OK.
  s6,

  /// Starts today (or the term runs, bike not handed over yet).
  s7,

  /// Running (bike handed over).
  s8,

  /// Running and ends today.
  s9,

  /// Nothing upcoming; a ride ended recently → review card + funnel.
  s10,
}

/// Snapshot of everything the Home v2 layout switches on.
class HomeSnapshot {
  final HomeTicket ticket;

  /// The booking the ticket is about (S2 when found in the list, S3–S9).
  final Reservation? res;
  final PendingBooking? pending;
  final PendingSosReplacement? sos;

  /// Completed booking of the review card (S10).
  final Reservation? review;

  /// Paid active / upcoming bookings (the same list today's Home showed).
  final List<Reservation> active;

  const HomeSnapshot({
    required this.ticket,
    this.res,
    this.pending,
    this.sos,
    this.review,
    this.active = const [],
  });

  bool get hasTicket => ticket != HomeTicket.s0 && ticket != HomeTicket.s10;

  /// "Další rezervace (n)" — the other paid bookings beside the ticket one.
  int get moreCount {
    final others = active.where((r) => r.id != res?.id).length;
    return others;
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Delivery pickup (address instead of a branch).
bool homeIsDelivery(Reservation r) =>
    r.pickupMethod == 'delivery' || (r.pickupAddress ?? '').trim().isNotEmpty;

/// Days from today to the booking start (0 = today).
int homeDaysUntil(Reservation r, DateTime now) => _day(r.startDate).difference(_day(now)).inDays;

/// Pure derivation (PLAN §2.1): S1 > S2 > S8/S9 > S7 > soonest upcoming
/// (S3/S4/S5/S6) > S10 > S0. [docsComplete] null = unknown (treated as OK,
/// exactly like the shell docs FAB). [hiddenReviews] = review cards the
/// customer hid (local pref).
HomeSnapshot deriveHomeState({
  required List<Reservation> reservations,
  PendingSosReplacement? sos,
  PendingBooking? pending,
  bool? docsComplete,
  Set<String> hiddenReviews = const {},
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = _day(n);
  // Same filter as today's Home list: only paid active / upcoming bookings.
  final active = reservations.where((r) {
    final s = r.displayStatus;
    return (s == ResStatus.aktivni || s == ResStatus.nadchazejici) && r.paymentStatus == 'paid';
  }).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));

  if (sos != null) {
    Reservation? res;
    for (final r in reservations) {
      if (r.id == sos.bookingId) res = r;
    }
    return HomeSnapshot(ticket: HomeTicket.s1, sos: sos, res: res, active: active);
  }
  if (pending != null && !pending.isExpired) {
    Reservation? res;
    for (final r in reservations) {
      if (r.id == pending.id) res = r;
    }
    return HomeSnapshot(ticket: HomeTicket.s2, pending: pending, res: res, active: active);
  }
  for (final r in active) {
    if (r.displayStatus == ResStatus.aktivni) {
      final endsToday = _day(r.endDate) == today;
      return HomeSnapshot(ticket: endsToday ? HomeTicket.s9 : HomeTicket.s8, res: r, active: active);
    }
  }
  // Starts today (or the term already runs, bike not handed over yet).
  for (final r in active) {
    if (!_day(r.startDate).isAfter(today)) {
      return HomeSnapshot(ticket: HomeTicket.s7, res: r, active: active);
    }
  }
  if (active.isNotEmpty) {
    final r = active.first;
    final HomeTicket t;
    if (docsComplete == false) {
      t = HomeTicket.s3;
    } else if (homeIsDelivery(r)) {
      t = HomeTicket.s5;
    } else if (r.isSelfService) {
      t = HomeTicket.s6;
    } else {
      t = HomeTicket.s4;
    }
    return HomeSnapshot(ticket: t, res: r, active: active);
  }
  // S10: the latest completed ride ended ≤ 14 days ago and is not rated, or
  // was rated within the last 24 h (the follow-up must stay reachable).
  Reservation? last;
  for (final r in reservations) {
    if (r.displayStatus != ResStatus.dokoncene) continue;
    if (last == null || r.endDate.isAfter(last.endDate)) last = r;
  }
  if (last != null && !hiddenReviews.contains(last.id)) {
    final age = today.difference(_day(last.endDate)).inDays;
    final ratedAt = last.ratedAt;
    final rateOpen = last.rating == null || (ratedAt != null && n.difference(ratedAt).inHours < 24);
    if (age >= 0 && age <= 14 && rateOpen) {
      return HomeSnapshot(ticket: HomeTicket.s10, review: last, active: active);
    }
  }
  return HomeSnapshot(ticket: HomeTicket.s0, active: active);
}
