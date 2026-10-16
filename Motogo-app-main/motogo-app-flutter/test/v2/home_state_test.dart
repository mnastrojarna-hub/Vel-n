// Home v2 state derivation (PLAN §5.5): S0–S10 incl. priorities and the
// 14-day / 24-h review window; funnel presets and licence filter.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_state.dart';

import 'support/fakes_home.dart';

void main() {
  final up6 = res('u6', status: 'reserved', from: 5, to: 7);
  final up4 = res('u4', status: 'reserved', from: 3, to: 5, self: false);
  final up5 = res('u5', status: 'reserved', from: 2, to: 4, self: false, delivery: true);
  final today = res('t7', status: 'reserved', from: 0, to: 2);
  final running = res('r8', status: 'active', from: -1, to: 1);
  final ending = res('r9', status: 'active', from: -2, to: 0);
  final done = res('d10', status: 'completed', from: -5, to: -3);
  final unpaid = res('p2', status: 'pending', pay: 'unpaid', from: 9, to: 11, created: DateTime.now().subtract(const Duration(minutes: 5)));
  final pending = PendingBooking(id: unpaid.id, totalPrice: 12027, createdAt: unpaid.createdAt);
  const sos = PendingSosReplacement(id: 's', type: 'theft', status: 'open', replacementStatus: 'selecting');

  HomeTicket t(List r, {PendingBooking? p, PendingSosReplacement? s, bool? docs = true, Set<String> hidden = const {}}) =>
      deriveHomeState(reservations: r.cast(), pending: p, sos: s, docsComplete: docs, hiddenReviews: hidden).ticket;

  test('no bookings → S0 (funnel)', () => expect(t([]), HomeTicket.s0));
  test('SOS beats everything', () => expect(t([running, up6], p: pending, s: sos), HomeTicket.s1));
  test('unpaid pending booking → S2 with its reservation', () {
    final snap = deriveHomeState(reservations: [unpaid, up6], pending: pending);
    expect(snap.ticket, HomeTicket.s2);
    expect(snap.res?.id, unpaid.id);
  });
  test('expired pending booking is ignored', () {
    final old = PendingBooking(id: unpaid.id, totalPrice: 1, createdAt: DateTime.now().subtract(const Duration(hours: 1)));
    expect(t([up6], p: old), HomeTicket.s6);
  });
  test('running → S8, ending today → S9, running beats upcoming', () {
    expect(t([up6, running]), HomeTicket.s8);
    expect(t([ending]), HomeTicket.s9);
  });
  test('starts today (not handed over) → S7', () => expect(t([today, up6]), HomeTicket.s7));
  test('soonest upcoming decides S3/S4/S5/S6', () {
    expect(t([up6], docs: false), HomeTicket.s3);
    expect(t([up4, up6]), HomeTicket.s4);
    expect(t([up5, up6]), HomeTicket.s5);
    expect(t([up6]), HomeTicket.s6);
    expect(t([up6], docs: null), HomeTicket.s6, reason: 'unknown docs = OK, like the shell FAB');
  });
  test('only paid bookings count (same as the old Home list)', () {
    expect(t([res('x', status: 'reserved', pay: 'unpaid', from: 3, to: 4)]), HomeTicket.s0);
  });
  test('S10 review window: ended ≤ 14 days, unrated or rated < 24 h', () {
    expect(t([done]), HomeTicket.s10);
    expect(t([res('d', status: 'completed', from: -20, to: -16)]), HomeTicket.s0);
    expect(t([res('d', status: 'completed', from: -5, to: -3, rating: 5, ratedAt: DateTime.now())]), HomeTicket.s10);
    expect(
        t([res('d', status: 'completed', from: -5, to: -3, rating: 5, ratedAt: DateTime.now().subtract(const Duration(days: 2)))]),
        HomeTicket.s0);
    expect(t([done], hidden: {done.id}), HomeTicket.s0, reason: 'Skrýt hides it');
    expect(t([done, up6]), HomeTicket.s6, reason: 'an upcoming booking wins');
  });
  test('moreCount = other paid bookings', () {
    expect(deriveHomeState(reservations: [up6, up4]).moreCount, 1);
    expect(deriveHomeState(reservations: [up6]).moreCount, 0);
  });

  test('weekend presets: nearest Fri–Sun (today when Friday) and the next one', () {
    for (var d = 0; d < 7; d++) {
      final now = DateTime(2026, 10, 12 + d, 10); // Mon 12. 10. … Sun 18. 10.
      final (a, b) = funnelPresets(now);
      expect(a.start.weekday, DateTime.friday);
      expect(a.end.weekday, DateTime.sunday);
      expect(a.days, 3);
      expect(a.start.isBefore(DateTime(now.year, now.month, now.day)), isFalse);
      expect(b.start.difference(a.start).inDays, 7);
    }
    expect(funnelPresets(DateTime(2026, 10, 16, 9)).$1.start, DateTime(2026, 10, 16));
  });

  test('eligible bikes: licence filter, no trailers / closed branches, last bike first', () {
    final all = [...kMotos];
    final a2 = homeEligibleMotos(all, {'license_group': ['A2']}, const []);
    expect(a2.map((m) => m.id), ['m-shot'], reason: 'A2 covers only the Shotgun');
    final a = homeEligibleMotos(all, {'license_group': ['A']}, const []);
    expect(a.length, 3);
    final again = homeEligibleMotos(all, {'license_group': ['A']}, [
      res('old', status: 'completed', from: -30, to: -28),
    ]);
    expect(again.first.id, 'm-husq');
    expect(homeEligibleMotos(all, null, const []).length, 3, reason: 'no groups → no filter');
  });
}
