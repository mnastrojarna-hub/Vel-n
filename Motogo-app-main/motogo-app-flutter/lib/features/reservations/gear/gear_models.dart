import '../../../core/i18n/i18n_provider.dart' show AppTranslations, lastKnownAppLang;
import '../reservation_models.dart';

/// Výpůjčka JEN výbavy (`bookings.booking_kind='gear'`): naceněné řádky
/// `gear_lines` a mapování tvaru RPC `get_my_gear_bookings` /
/// `get_web_gear_booking` (`_gear_booking_json`) na [Reservation].

/// Pořadí druhů výbavy (helma → boty), jako web `_gearItems`.
const kGearTypes = ['helmet', 'jacket', 'pants', 'gloves', 'boots'];

/// Jeden naceněný řádek výpůjčky (komplet nebo kus) — `bookings.gear_lines[]`.
class GearLine {
  final String key;
  final String kind; // 'set' | 'item'
  final String label; // český název z ceníku (překlad dělá UI)
  final List<String> includes;
  final Map<String, String> sizes;
  final double perDay;
  final double? total;
  /// Kusy nepřevzaté při předání (`not_taken`, zapisuje kiosk/Velín).
  final List<String> notTaken;

  const GearLine({
    required this.key,
    required this.kind,
    required this.label,
    this.includes = const [],
    this.sizes = const {},
    this.perDay = 0,
    this.total,
    this.notTaken = const [],
  });

  bool get isSet => kind == 'set';

  /// Kusy řádku (komplet = jeho kusy, kus = on sám).
  List<String> get keys => includes.isNotEmpty ? includes : [key];

  factory GearLine.fromJson(Map<String, dynamic> j) {
    final key = '${j['key'] ?? ''}';
    final inc = j['includes'] is List ? (j['includes'] as List).map((e) => '$e').toList() : <String>[];
    final sz = <String, String>{};
    if (j['sizes'] is Map) {
      (j['sizes'] as Map).forEach((k, v) {
        final s = '${v ?? ''}'.trim();
        if (s.isNotEmpty) sz['$k'] = s;
      });
    }
    return GearLine(
      key: key,
      kind: '${j['kind'] ?? (inc.length > 1 ? 'set' : 'item')}',
      label: '${j['label'] ?? key}',
      includes: inc,
      sizes: sz,
      perDay: (j['price_per_day'] as num?)?.toDouble() ?? 0,
      total: (j['total'] as num?)?.toDouble(),
      notTaken: j['not_taken'] is List ? (j['not_taken'] as List).map((e) => '$e').toList() : const [],
    );
  }
}

/// Tolerantní parse `gear_lines` / RPC `lines` (chybný řádek se přeskočí).
List<GearLine> parseGearLines(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => GearLine.fromJson(Map<String, dynamic>.from(e))).toList();
}

/// Kusy výpůjčky `{key: size}` v pořadí helma → boty (velikost '' = neznámá).
Map<String, String> gearItemSizes(Reservation r) {
  final out = <String, String>{};
  for (final l in r.gearLines) {
    for (final k in l.keys) {
      out.putIfAbsent(k, () => l.sizes[k] ?? _sizeColumn(r, k) ?? '');
    }
  }
  if (out.isEmpty) {
    for (final k in kGearTypes) {
      final s = _sizeColumn(r, k);
      if ((s ?? '').isNotEmpty) out[k] = s!;
    }
  }
  final keys = out.keys.toList()
    ..sort((a, b) => _order(a).compareTo(_order(b)));
  return {for (final k in keys) k: out[k]!};
}

int _order(String k) {
  final i = kGearTypes.indexOf(k);
  return i < 0 ? 99 : i;
}

String? _sizeColumn(Reservation r, String key) => switch (key) {
      'helmet' => r.helmetSize,
      'jacket' => r.jacketSize,
      'pants' => r.pantsSize,
      'gloves' => r.glovesSize,
      'boots' => r.bootsSize,
      _ => null,
    };

/// Název řádku v jazyce appky: překlad z ceníku ([priceLabels], klíč →
/// popisek), u kusu i18n klíč druhu (`helmet`…), jinak český název z DB.
String gearLineLabel(GearLine l, AppTranslations tr, [Map<String, String>? priceLabels]) {
  final p = priceLabels?[l.key];
  if (p != null && p.trim().isNotEmpty) return p;
  if (!l.isSet && kGearTypes.contains(l.key)) {
    final v = tr.tr(l.key);
    if (v != l.key) return v;
  }
  return l.label;
}

/// Velikosti řádku v pořadí kusů („M, L, L, M“; bez velikosti nic).
String gearLineSizes(GearLine l) =>
    [for (final k in l.keys) if ((l.sizes[k] ?? '').isNotEmpty) l.sizes[k]!].join(', ');

/// Velikosti řádku pojmenovaně jako potvrzení výpůjčky (web done):
/// komplet „helma M, bunda L, …“ (němčina s velkým písmenem), kus jen „43“.
String gearLineNamedSizes(GearLine l, AppTranslations tr, [Map<String, String>? priceLabels]) {
  String name(String k) {
    final p = priceLabels?[k];
    final s = (p != null && p.trim().isNotEmpty) ? p : tr.tr(k);
    return tr.lang == 'de' ? s : s.toLowerCase();
  }

  return [
    for (final k in l.keys)
      if ((l.sizes[k] ?? '').isNotEmpty) l.isSet ? '${name(k)} ${l.sizes[k]}' : l.sizes[k]!,
  ].join(', ');
}

/// Souhrn kusů na kartu: „Komplet bez bot (M, L, L, M) · Boty 43“.
String gearSummary(Reservation r, AppTranslations tr, [Map<String, String>? priceLabels]) {
  if (r.gearLines.isEmpty) {
    return [
      for (final e in gearItemSizes(r).entries) [tr.tr(e.key), e.value].where((s) => s.isNotEmpty).join(' '),
    ].join(' · ');
  }
  return [
    for (final l in r.gearLines)
      () {
        final name = gearLineLabel(l, tr, priceLabels);
        final sz = gearLineSizes(l);
        if (sz.isEmpty) return name;
        return l.isSet ? '$name ($sz)' : '$name $sz';
      }(),
  ].join(' · ');
}

/// Název pobočky bez „MotoGo24 “ (jako web).
String gearBranchName(String? name) =>
    (name ?? '').replaceFirst(RegExp(r'^MotoGo24\s*'), '').trim();

/// Tvar `_gear_booking_json` (RPC) → [Reservation] s `bookingKind='gear'`.
Reservation gearReservationFromRpc(Map<String, dynamic> j) {
  final br = j['branch'] is Map ? Map<String, dynamic>.from(j['branch'] as Map) : const <String, dynamic>{};
  final lines = parseGearLines(j['lines'] ?? j['gear_lines']);
  final sizes = <String, String>{};
  for (final l in lines) {
    sizes.addAll(l.sizes);
  }
  if (j['sizes'] is Map) {
    (j['sizes'] as Map).forEach((k, v) => sizes.putIfAbsent('$k', () => '${v ?? ''}'));
  }
  String? sz(String k) => (sizes[k] ?? '').isEmpty ? null : sizes[k];
  DateTime? ts(Object? v) => v == null ? null : DateTime.tryParse('$v');
  final voucher = (j['voucher_amount'] as num?)?.toDouble();
  final disc = (j['discount_amount'] as num?)?.toDouble();
  return Reservation(
    id: '${j['id']}',
    motoName: AppTranslations.of(lastKnownAppLang).tr('gearBookingTitle'),
    branchId: br['id'] as String? ?? j['branch_id'] as String?,
    branchName: br['name'] as String?,
    branchAddress: br['address'] as String?,
    branchCity: br['city'] as String?,
    branchLat: (br['gps_lat'] as num?)?.toDouble(),
    branchLng: (br['gps_lng'] as num?)?.toDouble(),
    branchType: br['type'] as String?,
    status: j['status'] as String? ?? 'pending',
    paymentStatus: j['payment_status'] as String? ?? 'unpaid',
    startDate: DateTime.tryParse('${j['start_date'] ?? ''}') ?? DateTime.now(),
    endDate: DateTime.tryParse('${j['end_date'] ?? ''}') ?? DateTime.now(),
    pickupTime: j['pickup_time'] as String?,
    returnTime: j['return_time'] as String?,
    totalPrice: (j['total'] as num?)?.toDouble() ?? (j['total_price'] as num?)?.toDouble() ?? 0,
    discountAmount: (disc != null && disc > 0) ? disc : voucher,
    bookingSource: j['booking_source'] as String?,
    createdAt: ts(j['created_at']) ?? DateTime.now(),
    pickedUpAt: ts(j['picked_up_at']),
    originalStartDate: ts(j['original_start_date']),
    originalEndDate: ts(j['original_end_date']),
    modificationHistory: (j['modification_history'] is List)
        ? (j['modification_history'] as List)
            .whereType<Map>()
            .map((e) => ModificationEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const [],
    helmetSize: sz('helmet'),
    jacketSize: sz('jacket'),
    pantsSize: sz('pants'),
    glovesSize: sz('gloves'),
    bootsSize: sz('boots'),
    gearLines: lines,
    gearPerDay: (j['per_day'] as num?)?.toDouble() ?? (j['gear_per_day'] as num?)?.toDouble(),
    bookingKind: 'gear',
  );
}
