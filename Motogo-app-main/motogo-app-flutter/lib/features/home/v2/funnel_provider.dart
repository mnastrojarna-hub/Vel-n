import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_days.dart';
import '../../auth/auth_provider.dart';
import '../../booking/booking_validator.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/reservation_provider.dart';
import 'home_offer_provider.dart';

/// A date range of the Home funnel (calendar days, inclusive).
@immutable
class FunnelRange {
  final DateTime start;
  final DateTime end;
  FunnelRange(DateTime s, DateTime e)
      : start = DateTime(s.year, s.month, s.day),
        end = DateTime(e.year, e.month, e.day);

  int get days => calendarDaysInclusive(start, end);

  @override
  bool operator ==(Object other) => other is FunnelRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// "Nejbližší víkend" (the nearest Fri–Sun from today; today when it is a
/// Friday) and "Další víkend" (the one after).
(FunnelRange, FunnelRange) funnelPresets(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final toFri = (DateTime.friday - today.weekday + 7) % 7;
  final fri = DateTime(today.year, today.month, today.day + toFri);
  FunnelRange wk(DateTime f) => FunnelRange(f, DateTime(f.year, f.month, f.day + 2));
  return (wk(fri), wk(DateTime(fri.year, fri.month, fri.day + 7)));
}

/// What the funnel "Kdy" row shows: the dates the customer GAVE — nothing
/// given = no dates (owner v5.0.1: nothing ticked by default; the weekend
/// chips stay shortcuts).
@immutable
class FunnelSelection {
  final FunnelRange? given;
  const FunnelSelection([this.given]);

  FunnelRange? range(DateTime now) => given;

  /// -1 = no dates, 0 / 1 = that weekend preset is on, 2 = an own range
  /// (date line + ✕).
  int preset(DateTime now) {
    final g = given;
    if (g == null) return -1;
    final p = funnelPresets(now);
    return g == p.$1 ? 0 : (g == p.$2 ? 1 : 2);
  }

  @override
  bool operator ==(Object other) => other is FunnelSelection && other.given == given;

  @override
  int get hashCode => given.hashCode;
}

/// A remembered range still usable: not already started in the past (an
/// in-memory pick from days ago) — else null (= not given).
FunnelRange? funnelGivenRange(FunnelRange? r, DateTime now) {
  if (r == null || r.end.isBefore(r.start)) return null;
  return r.start.isBefore(DateTime(now.year, now.month, now.day)) ? null : r;
}

/// The last dates the customer gave — here or anywhere the app writes the
/// catalogue dates (`catalogFilterProvider`: Motorky, calculator, pill;
/// Domů writes them too, `homeGiveDates`), so they are never picked twice.
/// A catalogue reset (Domů tab, "Bez termínu") does not forget them; only
/// ✕ on the funnel does. In-memory, like the funnel selection before.
final funnelGivenProvider = StateProvider<FunnelRange?>((ref) {
  ref.listen(catalogFilterProvider.select((f) => (f.startDate, f.endDate)), (_, d) {
    final s = d.$1, e = d.$2;
    if (s != null && e != null) ref.controller.state = FunnelRange(s, e);
  });
  final f = ref.read(catalogFilterProvider);
  final s = f.startDate, e = f.endDate;
  return s != null && e != null ? FunnelRange(s, e) : null;
});

/// Calendar day of [now] (local midnight).
DateTime funnelDay(DateTime now) => DateTime(now.year, now.month, now.day);

/// "Today" of the funnel. `HomeFunnelV2` moves it on at midnight and when
/// the app comes back, so a range given for a day that is now in the past
/// is dropped (and never priced / sent to REZERVOVAT) without a restart.
final funnelTodayProvider = StateProvider<DateTime>((ref) => funnelDay(DateTime.now()));

final funnelSelectionProvider = Provider<FunnelSelection>(
    (ref) => FunnelSelection(funnelGivenRange(ref.watch(funnelGivenProvider), ref.watch(funnelTodayProvider))));

/// Customer licence groups (`profiles.license_group[]`), upper case.
List<String> homeLicenseGroups(Map<String, dynamic>? profile) =>
    ((profile?['license_group'] as List?) ?? const [])
        .map((e) => e.toString().trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toList();

/// Bikes the customer may rent at all: open branch, not a trailer, licence
/// allowed (same check as the booking validator; no groups → no filter),
/// kids' bikes only after the customer rented one. Fleet order
/// (`sort_order`); the offer card shuffles it (`homeOfferShuffle`) and the
/// last ridden bike keeps only its "Znovu" badge (owner v5.0.1).
List<Motorcycle> homeEligibleMotos(
  List<Motorcycle> all,
  Map<String, dynamic>? profile,
  List<Reservation> reservations,
) {
  final groups = homeLicenseGroups(profile);
  final done = reservations.where((r) => r.displayStatus == ResStatus.dokoncene).toList()
    ..sort((a, b) => b.endDate.compareTo(a.endDate));
  final kidsBefore = done.any((r) => r.category == 'detske');
  final list = all.where((m) {
    if (m.branchIsOpen == false || m.isTrailer) return false;
    if (m.category == 'detske' && !kidsBefore) return false;
    if (groups.isEmpty) return true;
    return BookingValidator.checkLicense(
          userLicenseGroups: groups,
          motoLicenseGroups: m.licenseGroupsOrFallback,
        ) ==
        null;
  }).toList();
  return list;
}

/// Id of the bike the customer rode last (badge "Znovu").
final homeLastBikeIdProvider = Provider<String?>((ref) {
  final list = ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
  Reservation? last;
  for (final r in list) {
    if (r.displayStatus != ResStatus.dokoncene) continue;
    if (last == null || r.endDate.isAfter(last.endDate)) last = r;
  }
  return last?.motoId;
});

/// EVERY bike free on every day of [range] (owner v5.0.1: no cap) —
/// availability through the EXISTING `motoAvailableForRange` (the same
/// check the catalogue date filter uses; read-only RPCs), checked in
/// batches in the offer order; each finished batch is published to
/// `funnelPartialProvider`, so the first bikes show quickly.
final funnelCandidatesProvider =
    FutureProvider.autoDispose.family<List<Motorcycle>, FunnelRange>((ref, range) async {
  final seed = ref.watch(homeOfferSeedProvider);
  final all = await ref.watch(motorcyclesProvider.future);
  final profile = ref.watch(profileProvider).valueOrNull;
  final reservations = ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
  final eligible = homeOfferShuffle(homeEligibleMotos(all, profile, reservations), seed);
  final out = <Motorcycle>[];
  const batch = 6;
  var alive = true;
  ref.onDispose(() => alive = false);
  for (var i = 0; i < eligible.length && alive; i += batch) {
    final chunk = eligible.skip(i).take(batch).toList();
    final ok = await Future.wait(chunk.map((m) => motoAvailableForRange(m.id, range.start, range.end)));
    for (var j = 0; j < chunk.length; j++) {
      if (ok[j]) out.add(chunk[j]);
    }
    if (alive && out.isNotEmpty && i + batch < eligible.length) {
      ref.read(funnelPartialProvider((range, seed)).notifier).state = List.of(out);
    }
  }
  return out;
});

/// The range the funnel shows and prices (given, else null = no dates).
/// Notifies only when the RANGE changes (`FunnelRange ==`): giving the
/// weekend already shown (a card tap) or a new day with the same range
/// does not.
final funnelRangeProvider =
    Provider<FunnelRange?>((ref) => ref.watch(funnelSelectionProvider).range(ref.watch(funnelTodayProvider)));

/// Index of the bike in the middle of the funnel carousel (the CTA and the
/// calculator row use it). In-memory UI state while Domů stays mounted
/// (Back from a bike detail = that bike); other dates (picked anywhere) or
/// a new order (`homeOfferSeedProvider`) start again at the first bike.
final funnelCenterProvider = StateProvider.autoDispose<int>((ref) {
  ref.watch(funnelRangeProvider);
  ref.watch(homeOfferSeedProvider);
  return 0;
});

/// Category label from the existing card keys (`motoCardCategory*`).
String homeCategoryKey(String? cat) => switch (cat) {
      'cestovni' => 'motoCardCategoryTravel',
      'detske' => 'motoCardCategoryChildren',
      'sportovni' => 'motoCardCategorySport',
      'naked' => 'motoCardCategoryNaked',
      'chopper' => 'motoCardCategoryChopper',
      'supermoto' => 'motoCardCategorySupermoto',
      _ => '',
    };
