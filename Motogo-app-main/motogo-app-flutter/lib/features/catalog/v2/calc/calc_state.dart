import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog_provider.dart';
import '../../moto_model.dart';

/// State of the v2 price calculator (PLAN §2.2.4): IN MEMORY only. It never
/// touches `bookingDraftProvider` / `catalogFilterProvider` until the user
/// taps REZERVOVAT (→ `startBookingFromSelection`) or "Zobrazit volné
/// motorky" (→ the same date write as the catalog date picker).
///
/// No pickup time here (owner 2026-10-22): the time is chosen only in the
/// booking form; the calculator prices the standard pickup (the form's
/// 09:00 default) and shows the 12:00 saving as information.
class CalcState {
  /// null = all branches.
  final String? branchId;
  final String? motoId;
  final DateTime? start;
  final DateTime? end;

  const CalcState({this.branchId, this.motoId, this.start, this.end});

  bool get hasRange => start != null && end != null;

  CalcState copyWith({
    String? Function()? branchId,
    String? Function()? motoId,
    DateTime? Function()? start,
    DateTime? Function()? end,
  }) =>
      CalcState(
        branchId: branchId != null ? branchId() : this.branchId,
        motoId: motoId != null ? motoId() : this.motoId,
        start: start != null ? start() : this.start,
        end: end != null ? end() : this.end,
      );
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

  /// Entry from Home ("Spočítat přesnou cenu ›"): bike and / or dates.
  void prefill({String? motoId, DateTime? start, DateTime? end}) {
    state = CalcState(
      branchId: state.branchId,
      motoId: motoId ?? state.motoId,
      start: start ?? state.start,
      end: end ?? (start != null ? null : state.end),
    );
  }
}

final calcStateProvider = StateNotifierProvider<CalcStateNotifier, CalcState>((_) => CalcStateNotifier());

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
