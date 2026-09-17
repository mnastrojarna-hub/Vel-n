import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import 'moto_model.dart';

/// Fetches all active motorcycles with branch info.
/// Mirrors enrichMOTOS() from api-core.js.
Future<List<Motorcycle>> _fetchMotorcycles() async {
  // active + maintenance: motorka v servisu zůstává v nabídce — servisní dny
  // blokuje kalendář (get_moto_booked_dates vrací status='service'), ostatní
  // volné dny jdou normálně rezervovat. unavailable/retired se nezobrazují.
  final res = await MotoGoSupabase.client
      .from('motorcycles')
      .select('*, branches(name, address, city, type)')
      .inFilter('status', ['active', 'maintenance'])
      // Pořadí = ruční „Pořadí zobrazení (1-X)" z Velína (motorcycles.sort_order),
      // stejné jako web (fetchMotos: sort_order asc nulls last, model asc) a
      // hero banner. Neočíslované (NULL) jdou ZA očíslované podle modelu.
      .order('sort_order', ascending: true, nullsFirst: false)
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
}

/// Seznam motorek — REALTIME. Změna motorky ve Velíně / v DB (stav servisu,
/// pobočka, kóje, ceník…) se v katalogu, hledání, rezervačním formuláři i
/// změně/výměně motorky projeví hned, bez restartu appky. API stejné jako
/// dřívější FutureProvider (`.future`, `valueOrNull`, `invalidate`).
final motorcyclesProvider = StreamProvider<List<Motorcycle>>((ref) async* {
  try {
    yield await _fetchMotorcycles();
  } catch (e) {
    if (await handleAuthError(e)) {
      yield [];
      return;
    }
    rethrow;
  }

  // Realtime na `motorcycles` — první událost = počáteční snapshot tabulky
  // (data už máme), každá další = změna → znovu načíst vč. dostupnosti.
  // Chyby transportu neshazují UI (stejně jako reservationsProvider).
  try {
    var first = true;
    await for (final _ in MotoGoSupabase.client
        .from('motorcycles')
        .stream(primaryKey: ['id'])) {
      if (first) {
        first = false;
        continue;
      }
      try {
        yield await _fetchMotorcycles();
      } catch (e) {
        if (await handleAuthError(e)) return;
      }
    }
  } catch (e) {
    if (await handleAuthError(e)) return;
    return;
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
  final int? minPowerKw;
  final int? maxPowerKw;
  // Výška sedla (mm), točivý moment (Nm) a hmotnost (kg) — posuvníky od–do
  // ve filtru motorek. null = bez omezení na dané straně.
  final int? minSeatMm;
  final int? maxSeatMm;
  final int? minTorqueNm;
  final int? maxTorqueNm;
  final int? minWeightKg;
  final int? maxWeightKg;
  /// „Jen dnes volné" — dřív to bylo mrtvé zaškrtávátko, které jen leželo
  /// ve stavu obrazovky a nic nefiltrovalo.
  final bool availableTodayOnly;
  final List<String> usageTags;
  final DateTime? startDate;
  final DateTime? endDate;

  const CatalogFilter({
    this.category,
    this.licenseGroup,
    this.branch,
    this.minPowerKw,
    this.maxPowerKw,
    this.minSeatMm,
    this.maxSeatMm,
    this.minTorqueNm,
    this.maxTorqueNm,
    this.minWeightKg,
    this.maxWeightKg,
    this.availableTodayOnly = false,
    this.usageTags = const [],
    this.startDate,
    this.endDate,
  });

  CatalogFilter copyWith({
    String? Function()? category,
    String? Function()? licenseGroup,
    String? Function()? branch,
    int? Function()? minPowerKw,
    int? Function()? maxPowerKw,
    int? Function()? minSeatMm,
    int? Function()? maxSeatMm,
    int? Function()? minTorqueNm,
    int? Function()? maxTorqueNm,
    int? Function()? minWeightKg,
    int? Function()? maxWeightKg,
    bool? availableTodayOnly,
    List<String>? usageTags,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
  }) {
    return CatalogFilter(
      category: category != null ? category() : this.category,
      licenseGroup: licenseGroup != null ? licenseGroup() : this.licenseGroup,
      branch: branch != null ? branch() : this.branch,
      minPowerKw: minPowerKw != null ? minPowerKw() : this.minPowerKw,
      maxPowerKw: maxPowerKw != null ? maxPowerKw() : this.maxPowerKw,
      minSeatMm: minSeatMm != null ? minSeatMm() : this.minSeatMm,
      maxSeatMm: maxSeatMm != null ? maxSeatMm() : this.maxSeatMm,
      minTorqueNm: minTorqueNm != null ? minTorqueNm() : this.minTorqueNm,
      maxTorqueNm: maxTorqueNm != null ? maxTorqueNm() : this.maxTorqueNm,
      minWeightKg: minWeightKg != null ? minWeightKg() : this.minWeightKg,
      maxWeightKg: maxWeightKg != null ? maxWeightKg() : this.maxWeightKg,
      availableTodayOnly: availableTodayOnly ?? this.availableTodayOnly,
      usageTags: usageTags ?? this.usageTags,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
    );
  }

  /// Kolik filtrů je zapnutých — pro odznak u sbaleného panelu filtrů.
  int get activeCount =>
      (category == null ? 0 : 1) +
      (licenseGroup == null ? 0 : 1) +
      (branch == null ? 0 : 1) +
      (minPowerKw == null && maxPowerKw == null ? 0 : 1) +
      (minSeatMm == null && maxSeatMm == null ? 0 : 1) +
      (minTorqueNm == null && maxTorqueNm == null ? 0 : 1) +
      (minWeightKg == null && maxWeightKg == null ? 0 : 1) +
      (availableTodayOnly ? 1 : 0) +
      (startDate == null && endDate == null ? 0 : 1);

  /// Hodnota, kterou motorka nemá vyplněnou, filtrem VŽDY projde — stejně
  /// jako u výkonu. Jinak by zmizela hned, jak se posuvníkem hne.
  static bool _inRange(int? value, int? lo, int? hi) {
    // Nevyplněno = projde. Nula se bere jako NEVYPLNĚNO — `seat_height_mm`
    // má v DB DEFAULT 0, takže by jinak všechny takové motorky zmizely hned
    // po prvním pohnutí spodním jezdcem.
    if (value == null || value <= 0) return true;
    if (lo != null && value < lo) return false;
    if (hi != null && value > hi) return false;
    return true;
  }

  /// Apply filter to motorcycle list — mirrors applyFilters() from booking-calendar.js.
  List<Motorcycle> apply(List<Motorcycle> motos) {
    return motos.where((m) {
      if (category != null && m.category != category) return false;

      if (licenseGroup != null) {
        // Coverage: které skupiny ŘP motorky držitel zvolené skupiny "splní".
        // OR-match proti poli license_groups (fallback license_required).
        // 'N' (bez ŘP) je ve všech sadách → dětské/bez-ŘP vidí každý.
        const coverage = <String, List<String>>{
          'A': ['A', 'A2', 'A1', 'AM', 'N'],
          'A2': ['A2', 'A1', 'AM', 'N'],
          'A1': ['A1', 'AM', 'N'],
          'AM': ['AM', 'N'],
          'B': ['B', 'N'],
          'N': ['N'],
        };
        final covered = coverage[licenseGroup] ?? [licenseGroup!];
        final motoGroups = m.licenseGroupsOrFallback;
        if (motoGroups.isEmpty) return false;
        if (!motoGroups.any(covered.contains)) return false;
      }

      // Výkon od–do (posuvník na domů = rozsah, dropdown v hledání = jen max).
      // Motorka s NEVYPLNĚNÝM výkonem filtrem projde — stejně jako u ceny na
      // webu. Dřív se brala jako 0 kW a při pohnutí spodní hranicí tiše zmizela.
      final kw = m.powerKw;
      if (kw != null) {
        if (minPowerKw != null && kw < minPowerKw!) return false;
        if (maxPowerKw != null && kw > maxPowerKw!) return false;
      }
      if (branch != null && m.branchId != branch) return false;

      // Výška sedla / točivý moment / hmotnost — posuvníky od–do.
      if (!_inRange(m.seatHeightMm, minSeatMm, maxSeatMm)) return false;
      if (!_inRange(m.torqueNm, minTorqueNm, maxTorqueNm)) return false;
      if (!_inRange(m.weightKg, minWeightKg, maxWeightKg)) return false;

      // „Jen dnes volné" — motorka bez známé dostupnosti se nepočítá.
      if (availableTodayOnly && m.availableToday != true) return false;

      return true;
    }).toList();
  }
}

final catalogFilterProvider = StateProvider<CatalogFilter>(
  (_) => const CatalogFilter(),
);

/// Řazení výpisu motorek — sdílené mezi Domů a Rezervovat (obě obrazovky
/// používají stejný panel filtrů).
final catalogSortProvider = StateProvider<String>((_) => 'default');

/// Seřadí motorky podle volby z filtru.
List<Motorcycle> sortMotorcycles(List<Motorcycle> motos, String sort) {
  final list = List<Motorcycle>.from(motos);
  switch (sort) {
    case 'price_asc':
      list.sort((a, b) => (a.prices?.cheapest ?? 0).compareTo(b.prices?.cheapest ?? 0));
    case 'price_desc':
      list.sort((a, b) => (b.prices?.cheapest ?? 0).compareTo(a.prices?.cheapest ?? 0));
    case 'power_asc':
      list.sort((a, b) => (a.powerKw ?? 0).compareTo(b.powerKw ?? 0));
    case 'power_desc':
      list.sort((a, b) => (b.powerKw ?? 0).compareTo(a.powerKw ?? 0));
  }
  return list;
}

/// Meze posuvníků odvozené z DAT (ne napevno), aby se do rozsahu vešla každá
/// motorka ve skladu — jinak by krajní poloha posuvníku některé tiše vyřadila.
class MotoRange {
  final int min;
  final int max;
  const MotoRange(this.min, this.max);
  bool get valid => max > min;
}

class MotoRanges {
  final MotoRange power; // kW
  final MotoRange seat; // mm
  final MotoRange torque; // Nm
  final MotoRange weight; // kg
  const MotoRanges({
    required this.power,
    required this.seat,
    required this.torque,
    required this.weight,
  });
}

MotoRange _rangeOf(List<Motorcycle> motos, int? Function(Motorcycle) get,
    int fbLo, int fbHi, int step) {
  int? lo, hi;
  for (final m in motos) {
    final v = get(m);
    if (v == null || v <= 0) continue;
    if (lo == null || v < lo) lo = v;
    if (hi == null || v > hi) hi = v;
  }
  if (lo == null || hi == null || hi <= lo) return MotoRange(fbLo, fbHi);
  // Zaokrouhlení na „hezké" hodnoty ven z rozsahu, ať krajní motorka nevypadne.
  final rLo = (lo / step).floor() * step;
  final rHi = (hi / step).ceil() * step;
  return MotoRange(rLo, rHi > rLo ? rHi : rLo + step);
}

final motoRangesProvider = Provider<MotoRanges>((ref) {
  final motos = ref.watch(motorcyclesProvider).valueOrNull ?? const <Motorcycle>[];
  return MotoRanges(
    power: _rangeOf(motos, (m) => m.powerKw, 0, 200, 5),
    seat: _rangeOf(motos, (m) => m.seatHeightMm, 600, 950, 10),
    torque: _rangeOf(motos, (m) => m.torqueNm, 0, 200, 5),
    weight: _rangeOf(motos, (m) => m.weightKg, 80, 400, 10),
  );
});

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
  static const scootery = 'scootery';
  static const ostatni = 'ostatni';

  static const labels = <String?, String>{
    null: 'Vše',
    'cestovni': 'Cestovní / Enduro',
    'sportovni': 'Sportovní',
    'naked': 'Naked',
    'chopper': 'Chopper',
    'supermoto': 'Supermoto',
    'scootery': 'Skútry',
    'detske': 'Dětské',
    'ostatni': 'Ostatní',
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
