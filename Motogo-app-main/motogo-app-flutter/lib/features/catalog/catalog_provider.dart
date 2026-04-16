import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import 'moto_model.dart';

/// Fetches all active motorcycles with branch info.
/// Mirrors enrichMOTOS() from api-core.js.
final motorcyclesProvider = FutureProvider<List<Motorcycle>>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('motorcycles')
        .select('*, branches(name, address, city)')
        .eq('status', 'active')
        .order('model');

    final motos = (res as List).map((e) => Motorcycle.fromJson(e)).toList();

    // Batch-check today's availability for badge display
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final checks = await Future.wait(
      motos.map((m) => checkMotoAvailability(m.id, todayStart, todayEnd)),
    );
    return [
      for (int i = 0; i < motos.length; i++)
        motos[i].withAvailableToday(checks[i]),
    ];
  } catch (e) {
    if (await handleAuthError(e)) return [];
    rethrow;
  }
});

/// Fetches booked date ranges for a specific motorcycle.
/// Mirrors RPC get_moto_booked_dates(p_moto_id).
final bookedDatesProvider =
    FutureProvider.family<List<BookedDateRange>, String>((ref, motoId) async {
  final res = await MotoGoSupabase.client
      .rpc('get_moto_booked_dates', params: {'p_moto_id': motoId});

  return (res as List)
      .map((e) => BookedDateRange.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Checks motorcycle availability for a date range.
/// DB: check_moto_availability(p_moto_id, p_start, p_end, p_exclude_booking_id)
Future<bool> checkMotoAvailability(String motoId, DateTime start, DateTime end, {String? excludeBookingId}) async {
  try {
    final params = <String, dynamic>{
      'p_moto_id': motoId,
      'p_start': start.toIso8601String(),
      'p_end': end.toIso8601String(),
    };
    if (excludeBookingId != null) params['p_exclude_booking_id'] = excludeBookingId;
    final res = await MotoGoSupabase.client.rpc('check_moto_availability', params: params);
    return res == true;
  } catch (_) {
    return false;
  }
}

/// Current filter state for catalog/search screens.
class CatalogFilter {
  final String? category;
  final String? licenseGroup;
  final String? branch;
  final int? maxPowerKw;
  final List<String> usageTags;
  final DateTime? startDate;
  final DateTime? endDate;

  const CatalogFilter({
    this.category,
    this.licenseGroup,
    this.branch,
    this.maxPowerKw,
    this.usageTags = const [],
    this.startDate,
    this.endDate,
  });

  CatalogFilter copyWith({
    String? Function()? category,
    String? Function()? licenseGroup,
    String? Function()? branch,
    int? Function()? maxPowerKw,
    List<String>? usageTags,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
  }) {
    return CatalogFilter(
      category: category != null ? category() : this.category,
      licenseGroup: licenseGroup != null ? licenseGroup() : this.licenseGroup,
      branch: branch != null ? branch() : this.branch,
      maxPowerKw: maxPowerKw != null ? maxPowerKw() : this.maxPowerKw,
      usageTags: usageTags ?? this.usageTags,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
    );
  }

  /// Apply filter to motorcycle list — mirrors applyFilters() from booking-calendar.js.
  List<Motorcycle> apply(List<Motorcycle> motos) {
    return motos.where((m) {
      if (category != null && m.category != category) return false;

      if (licenseGroup != null) {
        final rp = m.licenseRequired ?? '';
        if (licenseGroup == 'A2') {
          if (!['A2', 'A1', 'AM', 'N'].contains(rp)) return false;
        } else if (rp != licenseGroup) {
          return false;
        }
      }

      if (maxPowerKw != null && (m.powerKw ?? 0) > maxPowerKw!) return false;
      if (branch != null && m.branchId != branch) return false;

      return true;
    }).toList();
  }
}

final catalogFilterProvider = StateProvider<CatalogFilter>(
  (_) => const CatalogFilter(),
);

/// Filtered motorcycles — combines provider + filter + availability check.
final filteredMotorcyclesProvider = FutureProvider<List<Motorcycle>>((ref) async {
  final motos = await ref.watch(motorcyclesProvider.future);
  final filter = ref.watch(catalogFilterProvider);
  final filtered = filter.apply(motos);

  // If dates selected, filter by availability (parallel checks)
  if (filter.startDate != null && filter.endDate != null) {
    final checks = await Future.wait(
      filtered.map((m) => checkMotoAvailability(m.id, filter.startDate!, filter.endDate!)),
    );
    return [
      for (int i = 0; i < filtered.length; i++)
        if (checks[i]) filtered[i],
    ];
  }

  return filtered;
});

/// Holds the ordered list of motorcycle IDs from the last filtered view.
/// Used by MotoDetailScreen pager to enable swiping between motorcycles.
final filteredMotoIdsProvider = StateProvider<List<String>>((_) => []);

/// Unique branches extracted from motorcycles data for filter dropdown.
final branchesProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final motos = ref.watch(motorcyclesProvider);
  return motos.when(
    data: (list) {
      final seen = <String>{};
      final branches = <Map<String, dynamic>>[];
      for (final m in list) {
        if (m.branchId != null && !seen.contains(m.branchId)) {
          seen.add(m.branchId!);
          branches.add({
            'id': m.branchId!,
            'name': m.branchName ?? m.branchCity ?? m.branchId!,
          });
        }
      }
      return branches;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Category definitions — mirrors the filter chips from templates-screens.js.
class MotoCategory {
  static const all = null;
  static const cestovni = 'cestovni';
  static const detske = 'detske';
  static const sportovni = 'sportovni';
  static const naked = 'naked';
  static const chopper = 'chopper';
  static const supermoto = 'supermoto';

  static const labels = <String?, String>{
    null: 'Vše',
    'cestovni': 'Cestovní / Enduro',
    'detske': 'Dětské',
    'sportovni': 'Sportovní',
    'naked': 'Naked',
    'chopper': 'Chopper',
    'supermoto': 'Supermoto',
  };
}
