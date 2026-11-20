import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/booking_rules.dart' show pragueWallClock;
import '../../core/supabase_client.dart';
import 'gear_contract.dart';
import 'gear_quote.dart';

/// Pobočka nabízená k výpůjčce výbavy (jako web pujceni-obleceni.php).
class GearBranch {
  final String id;
  final String name;
  final String address;
  final bool self;
  const GearBranch({required this.id, required this.name, this.address = '', this.self = false});
}

const String kGearSelfServiceType = 'samoobslužná';

/// Řádky `branches` → pobočky výbavy: jen `is_open` (dotaz), bez
/// `active=false`, samoobslužná jen při `self_service_enabled`; název bez
/// „MotoGo24 “, adresa „ulice, město“.
List<GearBranch> gearBranchesFrom(List<dynamic> rows, GearRentalSettings cfg) {
  final out = <GearBranch>[];
  for (final r in rows) {
    if (r is! Map) continue;
    final id = '${r['id'] ?? ''}';
    if (id.isEmpty || r['active'] == false || r['is_open'] == false) continue;
    final self = r['type'] == kGearSelfServiceType;
    if (self && !cfg.selfServiceEnabled) continue;
    final name = '${r['name'] ?? ''}'.replaceFirst(RegExp(r'^MotoGo24\s*', caseSensitive: false), '').trim();
    final addr = [r['address'], r['city']]
        .map((e) => '${e ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
    out.add(GearBranch(id: id, name: name, address: addr, self: self));
  }
  return out;
}

final gearBranchesProvider = FutureProvider<List<GearBranch>>((ref) async {
  final cfg = await ref.watch(gearRentalSettingsProvider.future);
  try {
    final rows = await MotoGoSupabase.client
        .from('branches')
        .select('*')
        .eq('is_open', true)
        .order('name', ascending: true);
    return gearBranchesFrom(rows, cfg);
  } catch (_) {
    return const [];
  }
});

/// Dnešek v Praze (datum).
DateTime gearPragueToday([DateTime? now]) => gearDate(pragueWallClock(now ?? DateTime.now()));

DateTime? _day(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}'.length >= 10 ? '${v ?? ''}'.substring(0, 10) : '');
  return d == null ? null : gearDate(d);
}

List<GearClosure> gearClosuresFrom(List<dynamic> rows) => [
      for (final r in rows)
        if (r is Map && _day(r['closed_from']) != null && _day(r['closed_to']) != null)
          GearClosure('${r['branch_id'] ?? ''}', _day(r['closed_from'])!, _day(r['closed_to'])!),
    ];

/// `branch_closures` s koncem od dneška (veřejné čtení).
final gearClosuresProvider = FutureProvider<List<GearClosure>>((ref) async {
  try {
    final rows = await MotoGoSupabase.client
        .from('branch_closures')
        .select('branch_id,closed_from,closed_to')
        .gte('closed_to', gearIso(gearPragueToday()));
    return gearClosuresFrom(rows);
  } catch (_) {
    return const [];
  }
});

/// Vstup „Půjčit samotnou výbavu“ na Domů: služba zapnutá a viditelná
/// v appce (`enabled && app_visible`), ceník není prázdný a je aspoň jedna
/// nabízená pobočka. Celý rok jako web (majitel 2026-11-20): zavřené dny
/// pobočky (`branch_closures`) jen nejdou vybrat v kalendáři objednávky.
bool gearEntryVisible(
  GearRentalSettings cfg,
  List<GearPrice> prices,
  List<GearBranch> branches,
) =>
    cfg.enabled && cfg.appVisible && prices.isNotEmpty && branches.isNotEmpty;

final gearRentEntryProvider = FutureProvider<bool>((ref) async {
  final cfg = await ref.watch(gearRentalSettingsProvider.future);
  if (!cfg.enabled || !cfg.appVisible) return false;
  final prices = await ref.watch(gearPricesProvider.future);
  final branches = await ref.watch(gearBranchesProvider.future);
  return gearEntryVisible(cfg, prices, branches);
});
