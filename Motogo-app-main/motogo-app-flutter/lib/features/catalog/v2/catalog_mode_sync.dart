import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog_provider.dart';
import '../moto_model.dart';
import 'calc/calc_state.dart';

/// One trip for the whole Motorky tab (owner 2026-10-22, „nikdy nic
/// vyplňovat dvakrát“): the list keeps its dates / branch in
/// `catalogFilterProvider`, the calculator in `calcStateProvider` (in
/// memory). Switching the mode carries what the customer set in the mode
/// being left — the newer choice — into the other one, with the SAME writes
/// as the existing pickers (calculator `setRange` / `setBranch`, the list's
/// date sheet / branch chip = "Zobrazit volné motorky"). Nothing is cleared:
/// a mode without dates / branch leaves the other one as it is.

/// Leaving "Najít motorku" → calculator: the list's range and branch. The
/// branch is skipped when it would drop the bike already picked in the
/// calculator (`setBranch` drops a bike from another branch).
void catCarryListToCalc(WidgetRef ref) {
  final f = ref.read(catalogFilterProvider);
  final st = ref.read(calcStateProvider);
  final n = ref.read(calcStateProvider.notifier);
  final s = f.startDate, e = f.endDate;
  if (s != null && e != null && (st.start != s || st.end != e)) n.setRange(s, e);
  final b = f.branch;
  if (b == null || st.branchId == b) return;
  Motorcycle? moto;
  for (final m in ref.read(motorcyclesProvider).valueOrNull ?? const <Motorcycle>[]) {
    if (m.id == st.motoId) moto = m;
  }
  if (st.motoId == null || moto?.branchId == b) n.setBranch(b, currentMoto: moto);
}

/// Leaving the calculator → "Najít motorku": its range and branch, one
/// write (the list re-checks availability once).
void catCarryCalcToList(WidgetRef ref) {
  final next = filterFromCalc(ref.read(calcStateProvider), ref.read(catalogFilterProvider));
  if (next != null) ref.read(catalogFilterProvider.notifier).state = next;
}

/// The filter after [catCarryCalcToList]; null = nothing to change.
CatalogFilter? filterFromCalc(CalcState st, CatalogFilter f) {
  var next = f;
  if (st.hasRange && (f.startDate != st.start || f.endDate != st.end)) {
    next = next.copyWith(startDate: () => st.start, endDate: () => st.end);
  }
  if (st.branchId != null && f.branch != st.branchId) {
    next = next.copyWith(branch: () => st.branchId);
  }
  return identical(next, f) ? null : next;
}

/// The calculator follows a full range written to the catalog while it is
/// shown (dates picked in a bike detail opened from "Detail ›", Home's
/// date sheet) — back in the calculator they are not picked again.
void catCalcFollowFilter(WidgetRef ref, CatalogFilter? prev, CatalogFilter next) {
  final s = next.startDate, e = next.endDate;
  if (s == null || e == null || (prev?.startDate == s && prev?.endDate == e)) return;
  final st = ref.read(calcStateProvider);
  if (st.start != s || st.end != e) ref.read(calcStateProvider.notifier).setRange(s, e);
}
