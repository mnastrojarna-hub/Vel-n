import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/v2/home_offer_provider.dart' show HomeClosure, homeClosuresProvider;
import '../catalog_provider.dart';
import '../moto_model.dart';

/// Days on which EVERY branch the customer can rent from is closed
/// (`branch_closures`, public read), as calendar ranges (status
/// `branch_closed`): the Motorky calendar draws them like booked days, so
/// it never offers closed days as free (5.0.1 re-check VR-03). [branch]
/// set = only that branch counts. Failure / no closure → none.
List<BookedDateRange> motorkyClosedDays(List<Motorcycle> motos, List<HomeClosure> closures,
    {String? branch, DateTime? now}) {
  final branches = branch != null
      ? {branch}
      : {for (final m in motos) if (m.branchIsOpen != false && !m.isTrailer && m.branchId != null) m.branchId!};
  if (branches.isEmpty || closures.isEmpty) return const [];
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  var last = today;
  for (final c in closures) {
    if (c.to.isAfter(last)) last = c.to;
  }
  bool closed(DateTime d) =>
      branches.every((b) => closures.any((c) => c.branchId == b && !d.isBefore(c.from) && !d.isAfter(c.to)));
  final out = <BookedDateRange>[];
  DateTime? from;
  for (var d = today; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
    final c = closed(d);
    if (c) from ??= d;
    if (!c && from != null) {
      out.add(BookedDateRange(start: from, end: DateTime(d.year, d.month, d.day - 1), status: 'branch_closed'));
      from = null;
    }
  }
  if (from != null) out.add(BookedDateRange(start: from, end: last, status: 'branch_closed'));
  return out;
}

/// [motorkyClosedDays] for the shared catalogue filter's branch.
final motorkyClosedDaysProvider = Provider.autoDispose<List<BookedDateRange>>((ref) {
  final motos = ref.watch(motorcyclesProvider).valueOrNull ?? const <Motorcycle>[];
  final closures = ref.watch(homeClosuresProvider).valueOrNull ?? const <HomeClosure>[];
  final branch = ref.watch(catalogFilterProvider.select((f) => f.branch));
  return motorkyClosedDays(motos, closures, branch: branch);
});
