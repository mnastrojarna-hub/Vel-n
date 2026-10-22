import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_days.dart';
import '../../auth/auth_provider.dart';
import '../../booking/booking_validator.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/reservation_provider.dart';

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

/// What the funnel "Kdy" row has selected: preset 0 / 1, or a custom range
/// from the calendar sheet (preset 2). In-memory only.
@immutable
class FunnelSelection {
  final int preset;
  final FunnelRange? custom;
  const FunnelSelection(this.preset, [this.custom]);

  FunnelRange range(DateTime now) {
    if (preset == 2 && custom != null) return custom!;
    final p = funnelPresets(now);
    return preset == 1 ? p.$2 : p.$1;
  }
}

final funnelSelectionProvider = StateProvider<FunnelSelection>((_) => const FunnelSelection(0));

/// Customer licence groups (`profiles.license_group[]`), upper case.
List<String> homeLicenseGroups(Map<String, dynamic>? profile) =>
    ((profile?['license_group'] as List?) ?? const [])
        .map((e) => e.toString().trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toList();

/// Bikes the customer may rent at all: open branch, not a trailer, licence
/// allowed (same check as the booking validator; no groups → no filter),
/// kids' bikes only after the customer rented one. Order: the last
/// completed booking's bike first, then the fleet order (`sort_order`).
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
  final lastId = done.isEmpty ? null : done.first.motoId;
  if (lastId != null) {
    final i = list.indexWhere((m) => m.id == lastId);
    if (i > 0) list.insert(0, list.removeAt(i));
  }
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

/// Up to 5 bikes free on every day of [range] — availability through the
/// EXISTING `motoAvailableForRange` (the same check the catalogue date
/// filter uses; read-only RPCs), checked in small batches in list order.
final funnelCandidatesProvider =
    FutureProvider.autoDispose.family<List<Motorcycle>, FunnelRange>((ref, range) async {
  final all = await ref.watch(motorcyclesProvider.future);
  final profile = ref.watch(profileProvider).valueOrNull;
  final reservations = ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
  final eligible = homeEligibleMotos(all, profile, reservations);
  final out = <Motorcycle>[];
  const batch = 6;
  for (var i = 0; i < eligible.length && out.length < 5; i += batch) {
    final chunk = eligible.skip(i).take(batch).toList();
    final ok = await Future.wait(chunk.map((m) => motoAvailableForRange(m.id, range.start, range.end)));
    for (var j = 0; j < chunk.length && out.length < 5; j++) {
      if (ok[j]) out.add(chunk[j]);
    }
  }
  return out;
});

/// Index of the bike in the middle of the funnel carousel (the CTA and the
/// ½ offer line use it). In-memory UI state.
final funnelCenterProvider = StateProvider<int>((_) => 0);

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
