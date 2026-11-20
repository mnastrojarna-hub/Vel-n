import 'dart:math' as math;

import '../booking/self_service_gear.dart';
import 'gear_contract.dart';

/// Čisté výpočty objednávky výbavy — zrcadlo webu `js/gear-rental.js`
/// (nacenění = SQL `_gear_rental_quote`, velikosti, sklad, kalendář).

/// Klientské nacenění: komplety (od největšího, pak nejlevnější) jen když
/// jsou vybrané VŠECHNY jejich kusy a komplet je levnější než jejich součet;
/// zbytek po kusech. [save] = součet kusů − cena za den.
class GearQuote {
  final List<GearPrice> lines;
  final double perDay;
  final double save;
  const GearQuote(this.lines, this.perDay, this.save);
}

List<GearPrice> gearItemsOf(List<GearPrice> prices) =>
    prices.where((p) => !p.isSet).toList(growable: false);

List<GearPrice> gearSetsOf(List<GearPrice> prices) =>
    prices.where((p) => p.isSet).toList(growable: false);

/// Komplety v pořadí nacenění (počet kusů ↓, cena ↑, klíč).
List<GearPrice> gearSetsSorted(List<GearPrice> prices) {
  final s = gearSetsOf(prices).toList();
  s.sort((a, b) {
    final n = b.includes.length - a.includes.length;
    if (n != 0) return n;
    final p = a.perDay.compareTo(b.perDay);
    if (p != 0) return p;
    return a.key.compareTo(b.key);
  });
  return s;
}

/// Vybrané kusy v pořadí ceníku (jako web `keys()`).
List<String> gearSelectedKeys(List<GearPrice> prices, Map<String, String> sel) =>
    [for (final p in gearItemsOf(prices)) if (sel.containsKey(p.key)) p.key];

GearQuote gearQuote(List<GearPrice> prices, Map<String, String> sel) {
  final by = {for (final p in prices) p.key: p};
  var left = gearSelectedKeys(prices, sel);
  final lines = <GearPrice>[];
  var per = 0.0, single = 0.0;
  for (final k in left) {
    single += by[k]!.perDay;
  }
  for (final s in gearSetsSorted(prices)) {
    if (s.includes.isEmpty || !s.includes.every(left.contains)) continue;
    var sum = 0.0;
    for (final k in s.includes) {
      sum += by[k]?.perDay ?? 0;
    }
    if (!(s.perDay < sum)) continue;
    lines.add(s);
    per += s.perDay;
    left = left.where((k) => !s.includes.contains(k)).toList();
  }
  for (final p in gearItemsOf(prices)) {
    if (left.contains(p.key)) {
      lines.add(p);
      per += p.perDay;
    }
  }
  return GearQuote(lines, per, math.max(0, single - per));
}

/// Je komplet [s] „stisknutý“ = vybrané jsou přesně jeho kusy.
bool gearSetOn(GearPrice s, List<GearPrice> prices, Map<String, String> sel) =>
    s.includes.every(sel.containsKey) &&
    gearSelectedKeys(prices, sel).length == s.includes.length;

/// Nabízené velikosti: samoobslužná pobočka jen v rozsahu kiosku.
List<String> gearSizesFor(GearPrice p, bool selfService) =>
    selfService ? selfServiceGearSizes(p.key, p.sizes) : p.sizes;

/// XXL = 2XL, XXXL = 3XL, XXXXL = 4XL (sklad i ceník píšou různě).
String gearNormSize(String? z) {
  final u = (z ?? '').trim().toUpperCase();
  return const {'XXL': '2XL', 'XXXL': '3XL', 'XXXXL': '4XL'}[u] ?? u;
}

/// Volný kus v termínu: sledovaný typ (klíč v `sizes`) jen s počtem > 0,
/// nesledovaný typ / vypnutá kontrola skladu ([avail] null) = bez omezení.
bool gearSizeFree(Map<String, dynamic>? avail, String key, String size) {
  final sizes = avail?['sizes'];
  final m = sizes is Map ? sizes[key] : null;
  if (m is! Map) return true;
  num? hit;
  m.forEach((k, v) {
    if (gearNormSize('$k') == gearNormSize(size)) {
      hit = v is num ? v : num.tryParse('$v') ?? 0;
    }
  });
  return hit != null && hit! > 0;
}

/// Velikost je nabízená i volná.
bool gearSizeOk(GearPrice p, String size, bool selfService, Map<String, dynamic>? avail) =>
    gearSizesFor(p, selfService).contains(size) && gearSizeFree(avail, p.key, size);

/// Prořezání výběru po změně pobočky / termínu / skladu: velikost, která už
/// nejde, se vymaže; vrací (nový výběr, [(velikost, název)] vypadlé kvůli skladu).
(Map<String, String>, List<(String, String)>) gearPrune(
  List<GearPrice> prices,
  Map<String, String> sel,
  bool selfService,
  Map<String, dynamic>? avail,
) {
  final by = {for (final p in prices) p.key: p};
  final out = Map<String, String>.from(sel);
  final dropped = <(String, String)>[];
  for (final k in gearSelectedKeys(prices, sel)) {
    final z = sel[k] ?? '';
    final p = by[k]!;
    if (z.isNotEmpty && !gearSizeOk(p, z, selfService, avail)) {
      out[k] = '';
      if (!gearSizeFree(avail, k, z)) dropped.add((z, p.label));
    }
  }
  return (out, dropped);
}

/// Vybráno vše potřebné pro serverovou cenu (web `complete()`).
bool gearComplete(
  List<GearPrice> prices,
  Map<String, String> sel, {
  required bool hasBranch,
  required DateTime? start,
  required DateTime? end,
}) {
  final ks = gearSelectedKeys(prices, sel);
  if (!hasBranch || start == null || end == null || ks.isEmpty) return false;
  final by = {for (final p in prices) p.key: p};
  return ks.every((k) => by[k]!.sizes.isEmpty || (sel[k] ?? '').isNotEmpty);
}

// ---- kalendář ----

enum GearDay { past, busy, free }

DateTime gearDate(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime gearAddDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Počet dní včetně obou krajních (web `K.count`).
int gearCountDays(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays + 1;

String gearIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Zavírací období pobočky (`branch_closures`, včetně krajních dní).
class GearClosure {
  final String branchId;
  final DateTime from;
  final DateTime to;
  const GearClosure(this.branchId, this.from, this.to);
}

bool gearClosed(List<GearClosure> closures, String? branchId, DateTime day) {
  if (branchId == null || branchId.isEmpty) return false;
  final d = gearDate(day);
  for (final c in closures) {
    if (c.branchId == branchId && !d.isBefore(c.from) && !d.isAfter(c.to)) return true;
  }
  return false;
}

/// Stav dne (web `st()`): minulost, obsazeno (za `max_ahead_days` nebo
/// zavřená pobočka), volno.
GearDay gearDayState(
  DateTime day, {
  required DateTime today,
  required int maxAhead,
  required List<GearClosure> closures,
  required String? branchId,
}) {
  final d = gearDate(day);
  if (d.isBefore(today)) return GearDay.past;
  if (d.isAfter(gearAddDays(today, maxAhead)) || gearClosed(closures, branchId, d)) return GearDay.busy;
  return GearDay.free;
}

/// Všechny dny rozsahu volné (web `rangeOk`).
bool gearRangeOk(
  DateTime a,
  DateTime b, {
  required DateTime today,
  required int maxAhead,
  required List<GearClosure> closures,
  required String? branchId,
}) {
  for (var x = gearDate(a); !x.isAfter(b); x = gearAddDays(x, 1)) {
    if (gearDayState(x, today: today, maxAhead: maxAhead, closures: closures, branchId: branchId) != GearDay.free) {
      return false;
    }
  }
  return true;
}
