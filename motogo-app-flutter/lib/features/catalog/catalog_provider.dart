import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import 'moto_model.dart';

/// Fetches all active motorcycles with branch info.
/// Mirrors enrichMOTOS() from api-core.js.
final motorcyclesProvider = FutureProvider<List<Motorcycle>>((ref) async {
  final res = await MotoGoSupabase.client
      .from('motorcycles')
      .select('*, branches(name, address, city)')
      .eq('status', 'active')
      .order('model');

  return (res as List).map((e) => Motorcycle.fromJson(e)).toList();
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
/// Mirrors check_moto_availability RPC.
Future<bool> checkMotoAvailability(String motoId, DateTime start, DateTime end) async {
  try {
    final res = await MotoGoSupabase.client.rpc('check_moto_availability', params: {
      'p_moto_id': motoId,
      'p_start_date': start.toIso8601String().substring(0, 10),
      'p_end_date': end.toIso8601String().substring(0, 10),
    });
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

/// Filtered motorcycles — combines provider + filter.
final filteredMotorcyclesProvider = Provider<AsyncValue<List<Motorcycle>>>((ref) {
  final motos = ref.watch(motorcyclesProvider);
  final filter = ref.watch(catalogFilterProvider);
  return motos.whenData((list) => filter.apply(list));
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

  static const labels = {
    null: 'Vše',
    'cestovni': 'Cestovní / Enduro',
    'detske': 'Dětské',
    'sportovni': 'Sportovní',
    'naked': 'Naked',
    'chopper': 'Chopper',
    'supermoto': 'Supermoto',
  };
}
