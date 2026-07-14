import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import 'moto_model.dart';

/// Fetches all active motorcycles with branch info.
/// Mirrors enrichMOTOS() from api-core.js.
final motorcyclesProvider = FutureProvider<List<Motorcycle>>((ref) async {
  try {
    // active + maintenance: motorka v servisu zůstává v nabídce — servisní dny
    // blokuje kalendář (get_moto_booked_dates vrací status='service'), ostatní
    // volné dny jdou normálně rezervovat. unavailable/retired se nezobrazují.
    final res = await MotoGoSupabase.client
        .from('motorcycles')
        .select('*, branches(name, address, city, type)')
        .inFilter('status', ['active', 'maintenance'])
        .order('model');

    final motos = (res as List).map((e) => Motorcycle.fromJson(e)).toList();

    // Batch-check today's availability for badge display.
    // POZOR: get_moto_booked_dates (NE check_moto_availability) — zahrnuje i
    // SERVISNÍ bloky (status='service'), takže motorka v servisu se dnes
    // správně tváří jako nedostupná. check_moto_availability servis IGNORUJE
    // (kontroluje jen rezervace) → falešně ukazovala „dnes dostupné". Stejný
    // zdroj jako kalendář v detailu i jako web.
    final today = DateTime.now();
    final checks = await Future.wait(
      motos.map((m) => motoFreeToday(m.id, today)),
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
/// autoDispose → po opuštění detailu se zahodí a při dalším otevření se načte
/// čerstvá dostupnost (vč. nových rezervací/storn/servisních bloků).
final bookedDatesProvider =
    FutureProvider.autoDispose.family<List<BookedDateRange>, String>((ref, motoId) async {
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

/// „Dnes dostupné" pro katalogový odznak: motorka je dnes volná, když dnešek
/// nespadá do žádného blokovaného rozsahu z `get_moto_booked_dates` — což jsou
/// rezervace I SERVISNÍ bloky (status='service'). Narozdíl od
/// `check_moto_availability` (ta servis IGNORUJE → motorka v servisu ukazovala
/// „dnes dostupné"). Shodné s kalendářem v detailu i s webem. Chyba → false
/// (odznak se raději skryje, než by falešně sliboval dostupnost).
Future<bool> motoFreeToday(String motoId, DateTime today) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_moto_booked_dates', params: {'p_moto_id': motoId});
    final blocked = (res as List).any((e) =>
        BookedDateRange.fromJson(e as Map<String, dynamic>).containsDate(today));
    return !blocked;
  } catch (_) {
    return false;
  }
}

/// Dostupnost motorky pro zvolený termín v katalogovém filtru: musí projít
/// `check_moto_availability` (překryv rezervací, časově přesné) A ZÁROVEŇ nesmí
/// v rozsahu ležet SERVISNÍ blok (status='service') — ten `check_moto_availability`
/// ignoruje, takže bez této kontroly by motorka v servisu šla ve filtru vybrat.
/// Obě kontroly běží paralelně. Booking-kontrola je fail-closed (chyba → skryto),
/// servisní kontrola fail-open (výpadek nemá zbytečně skrývat motorky).
Future<bool> motoAvailableForRange(String motoId, DateTime start, DateTime end) async {
  final results = await Future.wait([
    checkMotoAvailability(motoId, start, end),
    _noServiceBlockInRange(motoId, start, end),
  ]);
  return results[0] && results[1];
}

/// V rozsahu [start..end] (dny inkluzivně) neleží žádný SERVISNÍ blok z
/// `get_moto_booked_dates`. Booking bloky se ignorují (řeší check_moto_availability
/// časově přesně) — tady jde jen o servis, aby se nezměnila overlap semantika
/// zpětných rezervací (den vrácení × den vyzvednutí). Chyba → true (fail-open).
Future<bool> _noServiceBlockInRange(String motoId, DateTime start, DateTime end) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_moto_booked_dates', params: {'p_moto_id': motoId});
    DateTime d(DateTime x) => DateTime(x.year, x.month, x.day);
    final s = d(start);
    final e = d(end);
    for (final item in (res as List)) {
      final r = BookedDateRange.fromJson(item as Map<String, dynamic>);
      if (r.status != 'service') continue;
      final rs = d(r.start);
      final re = d(r.end);
      if (!s.isAfter(re) && !rs.isAfter(e)) return false; // překryv se servisem
    }
    return true;
  } catch (_) {
    return true;
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

  // If dates selected, filter by availability (parallel checks).
  // motoAvailableForRange = rezervace (check_moto_availability, časově přesné)
  // A ZÁROVEŇ žádný SERVISNÍ blok v termínu — bez toho by šla motorka v servisu
  // ve filtru „vybrat" (check_moto_availability servis ignoruje).
  if (filter.startDate != null && filter.endDate != null) {
    final checks = await Future.wait(
      filtered.map((m) => motoAvailableForRange(m.id, filter.startDate!, filter.endDate!)),
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

  /// i18n klíč pro lokalizovaný název kategorie (filtr) — místo natvrdo psaného
  /// českého labelu výše. Klíče existují ve všech jazycích (translations_ext_1_*).
  static String labelKey(String? slug) {
    switch (slug) {
      case 'cestovni':
        return 'motoCardCategoryTravel';
      case 'sportovni':
        return 'motoCardCategorySport';
      case 'naked':
        return 'motoCardCategoryNaked';
      case 'chopper':
        return 'motoCardCategoryChopper';
      case 'supermoto':
        return 'motoCardCategorySupermoto';
      case 'scootery':
        return 'motoCardCategoryScooters';
      case 'detske':
        return 'motoCardCategoryChildren';
      case 'ostatni':
        return 'motoCardCategoryOther';
      default:
        return 'all'; // null = „Vše" / „Todo" / …
    }
  }
}
