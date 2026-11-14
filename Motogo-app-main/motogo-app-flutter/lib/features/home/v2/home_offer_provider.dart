import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_client.dart';
import '../../auth/auth_provider.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/reservation_provider.dart';
import 'funnel_provider.dart';

/// Order of the offer card (owner v5.0.1: "nesmí tam být po každý stejná"):
/// a new random seed every time Domů is mounted again (autoDispose — a tab
/// switch unmounts Home, a pushed bike detail does not, so Back shows the
/// same bike) and when the app comes back after a pause (`HomeFunnelV2`).
final homeOfferSeedProvider = StateProvider.autoDispose<int>((ref) => homeOfferNewSeed());

final _rnd = Random();
int homeOfferNewSeed() => _rnd.nextInt(1 << 31);

/// [list] shuffled by [seed] (the same seed = the same order).
List<Motorcycle> homeOfferShuffle(List<Motorcycle> list, int seed) => List.of(list)..shuffle(Random(seed));

/// The bike whose calendar the customer just picked dates from: shown first
/// in the list for those dates (when it is free then).
final homeOfferFocusProvider = StateProvider.autoDispose<String?>((ref) => null);

/// [list] with the bike [id] moved to the front (unchanged without it).
List<Motorcycle> homeOfferFocusFirst(List<Motorcycle> list, String? id) {
  if (id == null) return list;
  final i = list.indexWhere((m) => m.id == id);
  if (i <= 0) return list;
  return [list[i], ...list.take(i), ...list.skip(i + 1)];
}

/// Bikes found free so far while `funnelCandidatesProvider` still checks
/// the rest (first bikes show quickly; null = nothing yet).
/// Keyed by range and order seed, so a new order never shows an old list.
final funnelPartialProvider =
    StateProvider.autoDispose.family<List<Motorcycle>?, (FunnelRange, int)>((ref, key) => null);

/// Next free day of every bike (existing RPC `get_motos_availability_status`,
/// one call for the whole fleet: bookings, service, closed branch). Read
/// only; any failure → empty map (no badge).
final homeNextFreeProvider = FutureProvider.autoDispose<Map<String, DateTime>>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_motos_availability_status')
        .timeout(const Duration(seconds: 15));
    final out = <String, DateTime>{};
    for (final r in (res as List)) {
      final row = r as Map;
      final id = row['moto_id']?.toString();
      final d = DateTime.tryParse(row['next_available_date']?.toString() ?? '');
      if (id != null && d != null) out[id] = DateTime(d.year, d.month, d.day);
    }
    return out;
  } catch (_) {
    return const {};
  }
});

/// One closure period of a branch (`branch_closures`, public read).
class HomeClosure {
  final String branchId;
  final DateTime from;
  final DateTime to;
  const HomeClosure(this.branchId, this.from, this.to);

  /// The closure touches at least one day of [r].
  bool overlaps(FunnelRange r) => !from.isAfter(r.end) && !to.isBefore(r.start);
}

/// Closures that have not ended yet. Read only; failure → none (the card
/// then says "all booked" instead of "closed").
final homeClosuresProvider = FutureProvider.autoDispose<List<HomeClosure>>((ref) async {
  try {
    final now = DateTime.now();
    final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final res = await MotoGoSupabase.client
        .from('branch_closures')
        .select('branch_id, closed_from, closed_to')
        .gte('closed_to', today)
        .timeout(const Duration(seconds: 15));
    return [
      for (final r in (res as List))
        if (DateTime.tryParse('${(r as Map)['closed_from']}') case final f?)
          if (DateTime.tryParse('${r['closed_to']}') case final t?)
            HomeClosure('${r['branch_id']}', DateTime(f.year, f.month, f.day), DateTime(t.year, t.month, t.day)),
    ];
  } catch (_) {
    return const [];
  }
});

/// Every bike of [bikes] sits on a branch closed on some day of [range].
bool homeOfferAllClosed(List<Motorcycle> bikes, List<HomeClosure> closures, FunnelRange range) =>
    bikes.isNotEmpty &&
    bikes.every((m) => m.branchId != null && closures.any((c) => c.branchId == m.branchId && c.overlaps(range)));

/// What the offer card shows.
enum HomeOfferMode {
  /// Bikes / availability still loading (skeleton).
  loading,

  /// Could not load (retry).
  error,

  /// No dates given: every bike the customer may ride, "od" prices.
  noDates,

  /// Dates given: the bikes free on every day of them.
  free,

  /// Dates given, nothing free: still the bikes, with "Volná od".
  noneFree,

  /// No bike to offer at all.
  noBikes,
}

class HomeOffer {
  final HomeOfferMode mode;
  final List<Motorcycle> bikes;
  final FunnelRange? range;

  /// [noneFree]: every branch is closed in the dates (not booked out).
  final bool closed;

  /// [free]: more bikes are still being checked.
  final bool more;

  const HomeOffer(this.mode, {this.bikes = const [], this.range, this.closed = false, this.more = false});

  bool get hasBikes => bikes.isNotEmpty;
}

/// Bikes the customer may ride (`homeEligibleMotos`), in the offer order.
final homeOfferEligibleProvider = Provider.autoDispose<AsyncValue<List<Motorcycle>>>((ref) {
  final all = ref.watch(motorcyclesProvider);
  final profile = ref.watch(profileProvider).valueOrNull;
  final reservations = ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
  final seed = ref.watch(homeOfferSeedProvider);
  return all.whenData((a) => homeOfferShuffle(homeEligibleMotos(a, profile, reservations), seed));
});

/// The offer card's state for the dates given (or none).
final homeOfferProvider = Provider.autoDispose<HomeOffer>((ref) {
  final range = ref.watch(funnelRangeProvider);
  final eligible = ref.watch(homeOfferEligibleProvider);
  HomeOffer fromEligible(HomeOfferMode mode, {bool closed = false}) {
    final l = eligible.valueOrNull;
    if (l == null) return HomeOffer(eligible.hasError ? HomeOfferMode.error : HomeOfferMode.loading, range: range);
    return l.isEmpty ? HomeOffer(HomeOfferMode.noBikes, range: range) : HomeOffer(mode, bikes: l, range: range, closed: closed);
  }

  if (range == null) return fromEligible(HomeOfferMode.noDates);
  final cand = ref.watch(funnelCandidatesProvider(range));
  final focus = ref.watch(homeOfferFocusProvider);
  if (cand.hasValue) {
    final l = cand.requireValue;
    if (l.isNotEmpty) return HomeOffer(HomeOfferMode.free, bikes: homeOfferFocusFirst(l, focus), range: range);
    final closures = ref.watch(homeClosuresProvider).valueOrNull ?? const <HomeClosure>[];
    final bikes = eligible.valueOrNull ?? const <Motorcycle>[];
    return fromEligible(HomeOfferMode.noneFree, closed: homeOfferAllClosed(bikes, closures, range));
  }
  if (cand.hasError) return HomeOffer(HomeOfferMode.error, range: range);
  final part = ref.watch(funnelPartialProvider((range, ref.watch(homeOfferSeedProvider))));
  if (part != null && part.isNotEmpty) {
    return HomeOffer(HomeOfferMode.free, bikes: homeOfferFocusFirst(part, focus), range: range, more: true);
  }
  return HomeOffer(HomeOfferMode.loading, range: range);
});
