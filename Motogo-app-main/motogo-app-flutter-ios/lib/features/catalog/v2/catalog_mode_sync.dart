import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog_provider.dart';
import '../moto_model.dart';
import 'calc/calc_state.dart';
import 'catalog_date_sheet_v2.dart' show catClearDates, catSetDates;

/// One trip for the whole Motorky tab (owner 2026-10-22, „nikdy nic
/// vyplňovat dvakrát“): the list keeps its dates / branch in
/// `catalogFilterProvider`, the calculator in `calcStateProvider` (in
/// memory). A range picked (or cleared) in the calculator is written
/// through to the catalog at once (the same write as the catalog date
/// picker), so the list, the Home funnel / pill and a bike detail see it
/// even after a tab switch. Switching the mode carries what the customer
/// set in the mode being left — the newer choice — into the other one
/// (calculator `setRange` / `setBranch`, the list's date sheet / branch
/// chip). A clear is a choice too: dates cleared in one mode after the last
/// sync clear the other one ([catTripSyncedProvider]).

typedef CatTripDates = (DateTime?, DateTime?);

/// The dates both modes agreed on at the last sync (mode switch or a
/// calculator write-through); null = never synced — then a mode without
/// dates never clears the other one.
final catTripSyncedProvider = StateProvider<CatTripDates?>((_) => null);

CatTripDates _listDates(CatalogFilter f) => (f.startDate, f.endDate);

void _markSynced(WidgetRef ref, CatTripDates d) {
  if (ref.read(catTripSyncedProvider) != d) ref.read(catTripSyncedProvider.notifier).state = d;
}

bool _isRange(CatTripDates? d) => d != null && d.$1 != null && d.$2 != null;

/// Leaving "Najít motorku" → calculator: the list's range and branch. The
/// branch is skipped when it would drop the bike already picked in the
/// calculator (`setBranch` drops a bike from another branch). A list
/// cleared ("Bez termínu") since the last sync clears the calculator's
/// range from that sync.
void catCarryListToCalc(WidgetRef ref) {
  final f = ref.read(catalogFilterProvider);
  final st = ref.read(calcStateProvider);
  final n = ref.read(calcStateProvider.notifier);
  final synced = ref.read(catTripSyncedProvider);
  final s = f.startDate, e = f.endDate;
  if (s != null && e != null) {
    if (st.start != s || st.end != e) n.setRange(s, e);
  } else if (_isRange(synced) && st.start == synced!.$1 && st.end == synced.$2) {
    n.clearDates();
  }
  _markSynced(ref, _listDates(f));
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
  final f = ref.read(catalogFilterProvider);
  final next = filterFromCalc(ref.read(calcStateProvider), f, ref.read(catTripSyncedProvider));
  if (next != null) ref.read(catalogFilterProvider.notifier).state = next;
  _markSynced(ref, _listDates(next ?? f));
}

/// The filter after [catCarryCalcToList]; null = nothing to change. The
/// list's range is cleared only when the calculator was cleared after the
/// last sync ([synced]) and the list still shows that synced range.
CatalogFilter? filterFromCalc(CalcState st, CatalogFilter f, [CatTripDates? synced]) {
  var next = f;
  if (st.hasRange && (f.startDate != st.start || f.endDate != st.end)) {
    next = next.copyWith(startDate: () => st.start, endDate: () => st.end);
  } else if (st.start == null && st.end == null && _isRange(synced) && _listDates(f) == synced) {
    next = next.copyWith(startDate: () => null, endDate: () => null);
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
  _markSynced(ref, (s, e));
}

/// A range picked in the calculator: the calculator + the shared trip.
void catCalcSetRange(WidgetRef ref, DateTime s, DateTime e) {
  ref.read(calcStateProvider.notifier).setRange(s, e);
  final f = ref.read(catalogFilterProvider);
  if (f.startDate != s || f.endDate != e) catSetDates(ref, s, e);
  _markSynced(ref, (s, e));
}

/// "Smazat termín" / calendar reset in the calculator: the shared trip too.
void catCalcClearDates(WidgetRef ref) {
  ref.read(calcStateProvider.notifier).clearDates();
  final f = ref.read(catalogFilterProvider);
  if (f.startDate != null || f.endDate != null) catClearDates(ref);
  _markSynced(ref, (null, null));
}

/// A remount of Motorky after the calculator (any tab tap remounts the
/// tab, which starts in "Najít motorku"): the calculator's range reaches
/// the list unless the list's dates were changed elsewhere since the last
/// sync (an entry with its own dates wins; its branch is never touched).
void catCarryCalcDatesOnRemount(WidgetRef ref) {
  final st = ref.read(calcStateProvider);
  final f = ref.read(catalogFilterProvider);
  if (!st.hasRange || (f.startDate == st.start && f.endDate == st.end)) return;
  final synced = ref.read(catTripSyncedProvider);
  final untouched = synced == null ? f.startDate == null && f.endDate == null : _listDates(f) == synced;
  if (!untouched) return;
  catSetDates(ref, st.start!, st.end!);
  _markSynced(ref, (st.start, st.end));
}

/// Calendar day [d] is before today (local).
bool catBeforeToday(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(d.year, d.month, d.day).isBefore(DateTime(n.year, n.month, n.day));
}

/// A remembered trip that already started in the past (the app stayed
/// alive across days) is dropped — the same rule as the Home funnel
/// (`funnelGivenRange`): the list, the card CTA and the calculator never
/// offer a range the booking form would refuse.
void catDropPastDates(WidgetRef ref) {
  final f = ref.read(catalogFilterProvider);
  final s = f.startDate;
  if (s != null && catBeforeToday(s)) catClearDates(ref);
  final st = ref.read(calcStateProvider);
  final cs = st.start;
  if (cs != null && catBeforeToday(cs)) ref.read(calcStateProvider.notifier).clearDates();
  if ((s != null && catBeforeToday(s)) || (cs != null && catBeforeToday(cs))) _markSynced(ref, (null, null));
}
