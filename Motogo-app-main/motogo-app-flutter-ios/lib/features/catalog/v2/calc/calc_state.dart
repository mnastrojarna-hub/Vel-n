import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/booking_address_carry.dart' show HandoverChoice;
import '../../../payment/payment_provider.dart' show lastConfirmedBookingProvider;
import '../../catalog_provider.dart';
import '../../moto_model.dart';

/// State of the v2 price calculator (PLAN §2.2.4): IN MEMORY only. It never
/// touches `bookingDraftProvider` until the user taps REZERVOVAT (→
/// `startBookingFromSelection`). Dates picked / cleared here are written
/// through to `catalogFilterProvider` (one trip, `catalog_mode_sync.dart`:
/// the same write as the catalog date picker). A paid booking empties its
/// bike and dates (a clean start, like the booking draft).
///
/// No pickup time here (owner 2026-10-22): the time is chosen only in the
/// booking form; the calculator prices the standard pickup (the form's
/// 09:00 default) and shows the 12:00 saving as information.
///
/// The PLACE of the handover is chosen here too (owner 2026-11-27):
/// [handover] = pickup at the branch / delivery to an address, return at the
/// branch / collection — with the booking form's own sections and rules.
class CalcState {
  /// null = all branches.
  final String? branchId;
  final String? motoId;
  final DateTime? start;
  final DateTime? end;

  /// Handover chosen in step ④; null = not touched here (the step then
  /// shows what the booking form would open with).
  final CalcHandover? handover;

  const CalcState({this.branchId, this.motoId, this.start, this.end, this.handover});

  bool get hasRange => start != null && end != null;

  CalcState copyWith({
    String? Function()? branchId,
    String? Function()? motoId,
    DateTime? Function()? start,
    DateTime? Function()? end,
    CalcHandover? Function()? handover,
  }) =>
      CalcState(
        branchId: branchId != null ? branchId() : this.branchId,
        motoId: motoId != null ? motoId() : this.motoId,
        start: start != null ? start() : this.start,
        end: end != null ? end() : this.end,
        handover: handover != null ? handover() : this.handover,
      );
}

/// The handover the customer chose in the calculator: [choice] in the shape
/// the booking form holds it, for bikes of branch [branchId] (the form's
/// rule: another branch = back to the branch) and for account [owner] (an
/// address is never shown to another account on the same phone).
class CalcHandover {
  final HandoverChoice choice;
  final String? branchId;
  final String? owner;
  const CalcHandover({required this.choice, this.branchId, this.owner});

  bool validFor(String? branch, String? uid) => branchId == branch && owner == uid;
}

class CalcStateNotifier extends StateNotifier<CalcState> {
  CalcStateNotifier() : super(const CalcState());

  /// Branch change keeps the dates; a bike from another branch is dropped.
  void setBranch(String? id, {Motorcycle? currentMoto}) {
    final keepMoto = id == null || currentMoto == null || currentMoto.branchId == id;
    state = state.copyWith(branchId: () => id, motoId: keepMoto ? null : () => null);
  }

  void setMoto(String? id) => state = state.copyWith(motoId: () => id);

  void setRange(DateTime s, DateTime e) => state = state.copyWith(start: () => s, end: () => e);

  /// Start picked, end pending (calendar step 2).
  void setStart(DateTime s) => state = state.copyWith(start: () => s, end: () => null);

  void clearDates() => state = state.copyWith(start: () => null, end: () => null);

  /// After a paid booking: its bike, dates and handover go, the branch stays.
  void resetTrip() => state = CalcState(branchId: state.branchId);

  /// Entry from Home ("Spočítat přesnou cenu ›"): bike and / or dates.
  void prefill({String? motoId, DateTime? start, DateTime? end}) {
    state = CalcState(
      branchId: state.branchId,
      motoId: motoId ?? state.motoId,
      start: start ?? state.start,
      end: end ?? (start != null ? null : state.end),
      handover: state.handover,
    );
  }

  /// A change of the handover in step ④. [fn] gets the CURRENT choice — the
  /// address sheet reports the price and then the address, and the other
  /// side may take both over — or [seed] (what the step shows) when nothing
  /// valid for [branchId] / [owner] was chosen here yet.
  void updateHandover(
    HandoverChoice Function(HandoverChoice current) fn, {
    required HandoverChoice seed,
    required String? branchId,
    String? owner,
  }) {
    final cur = state.handover;
    final base = cur != null && cur.validFor(branchId, owner) ? cur.choice : seed;
    state = state.copyWith(handover: () => CalcHandover(choice: fn(base), branchId: branchId, owner: owner));
  }

  /// Handed over to the booking form (which holds it from then on).
  void clearHandover() {
    if (state.handover != null) state = state.copyWith(handover: () => null);
  }

  /// The booking form's normalizations for the bike now chosen: a choice
  /// made for another branch (or account) is dropped — the form's carry rule
  /// for another bike; where delivery is not offered ([blocked]) both sides
  /// go back to the branch — the form's self-service rule.
  void normalizeHandover({required String? branchId, required String? owner, required bool blocked}) {
    final cur = state.handover;
    if (cur == null) return;
    if (!cur.validFor(branchId, owner)) return clearHandover();
    final d = cur.choice.draft;
    if (blocked && (d.pickupMethod == 'delivery' || d.returnMethod == 'delivery')) {
      final c = cur.choice.copyWith(draft: d.copyWith(pickupMethod: 'store', returnMethod: 'store'));
      state = state.copyWith(handover: () => CalcHandover(choice: c, branchId: branchId, owner: owner));
    }
  }
}

final calcStateProvider = StateNotifierProvider<CalcStateNotifier, CalcState>((ref) {
  final n = CalcStateNotifier();
  // The next "Spočítat cenu" must not reopen the trip just booked (its own
  // days would show as busy) — the same signal the booking draft and the
  // Domů reset use for a clean start.
  ref.listen<String?>(lastConfirmedBookingProvider, (prev, next) {
    if (next != null && next != prev) n.resetTrip();
  });
  return n;
});

/// Bikes the calculator offers: the browse rule of `filteredMotorcyclesProvider`
/// (permanently closed branches never offered), narrowed to the branch.
List<Motorcycle> calcOffered(List<Motorcycle> all, String? branchId) => [
      for (final m in all)
        if (m.branchIsOpen != false && (branchId == null || m.branchId == branchId)) m,
    ];

/// "Volné v tvém termínu" without a chosen bike: the SAME read-only check
/// the catalog date filter uses (`motoAvailableForRange` per bike, parallel).
final calcFreeMotosProvider =
    FutureProvider.autoDispose.family<List<Motorcycle>, (String?, DateTime, DateTime)>((ref, k) async {
  final all = await ref.watch(motorcyclesProvider.future);
  final motos = calcOffered(all, k.$1);
  final checks = await Future.wait(motos.map((m) => motoAvailableForRange(m.id, k.$2, k.$3)));
  return [
    for (var i = 0; i < motos.length; i++)
      if (checks[i]) motos[i],
  ];
});
