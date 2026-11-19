import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase_client.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';

/// Výpůjčka jen výbavy (bookings.booking_kind='gear') — čtení přes RPC
/// (nezávisí na app_settings.gear_rental.app_visible). Sdílený kontrakt:
/// vlastní ho zobrazení rezervací, objednávka ho jen importuje.

/// Moje výpůjčky výbavy (RPC get_my_gear_bookings); [] při chybě / bez RPC.
/// GPS pobočky RPC nevrací → doplní se z veřejné tabulky `branches`.
Future<List<Reservation>> fetchMyGearBookings() async {
  try {
    final res = await MotoGoSupabase.client.rpc('get_my_gear_bookings');
    if (res is! List) return const [];
    final rows = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    await _attachBranchGps(rows);
    final out = <Reservation>[];
    for (final r in rows) {
      if (r['id'] == null) continue;
      try {
        out.add(Reservation.fromGearRpc(r));
      } catch (_) {/* vadný řádek nesmí shodit seznam */}
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Detail jedné výpůjčky výbavy (RPC get_web_gear_booking); null při chybě.
Future<Map<String, dynamic>?> fetchGearBookingJson(String bookingId) async {
  try {
    final res = await MotoGoSupabase.client.rpc('get_web_gear_booking',
        params: {'p_booking_id': bookingId, 'p_session_id': null});
    if (res is! Map) return null;
    final m = Map<String, dynamic>.from(res);
    if (m['error'] != null) return null;
    await _attachBranchGps([m]);
    return m;
  } catch (_) {
    return null;
  }
}

/// Doplní `branch.gps_lat/gps_lng` (RPC je nevrací) — navigace na pobočku
/// výpůjčky, ne na výchozí Mezná. Chyba = bez GPS (navigace podle adresy).
/// GPS poboček podle id (pobočka se nestěhuje) — detail se obnovuje po 5 s.
final Map<String, Map> _gpsCache = {};

Future<void> _attachBranchGps(List<Map<String, dynamic>> rows) async {
  String? idOf(Map<String, dynamic> r) =>
      r['branch'] is Map && (r['branch'] as Map)['id'] != null && (r['branch'] as Map)['gps_lat'] == null
          ? '${(r['branch'] as Map)['id']}'
          : null;
  final missing = {for (final r in rows) idOf(r)}..remove(null);
  missing.removeWhere(_gpsCache.containsKey);
  if (missing.isNotEmpty) {
    try {
      final res = await MotoGoSupabase.client
          .from('branches')
          .select('id, gps_lat, gps_lng')
          .inFilter('id', missing.whereType<String>().toList());
      for (final b in (res as List).whereType<Map>()) {
        _gpsCache['${b['id']}'] = b;
      }
    } catch (_) {/* bez GPS */}
  }
  for (final r in rows) {
    final id = idOf(r);
    final g = id == null ? null : _gpsCache[id];
    if (g == null) continue;
    r['branch'] = {...Map<String, dynamic>.from(r['branch'] as Map), 'gps_lat': g['gps_lat'], 'gps_lng': g['gps_lng']};
  }
}

/// Kam se scanner dokladů vrátí po dokončení (null = Moje doklady, jako
/// dosud). Nastaví [openGearIdDocs]; scanner hodnotu po použití vynuluje.
final docScanReturnRouteProvider = StateProvider<String?>((_) => null);

/// Nahrání dokladu totožnosti (OP obě strany / pas) k výpůjčce výbavy —
/// ŘP se nevyžaduje. Po dokončení scanneru zpět na detail rezervace.
Future<void> openGearIdDocs(
    BuildContext context, WidgetRef ref, String bookingId) async {
  ref.read(docScanReturnRouteProvider.notifier).state = '/reservations/$bookingId';
  await context.push('/docs/scan?mode=missing_id');
  if (!context.mounted) return;
  // Zpět (bez dokončení) → návrat nezůstane viset pro příští sken.
  ref.read(docScanReturnRouteProvider.notifier).state = null;
  refreshGearBookings(ref, bookingId);
}

/// Znovu načíst rezervace po akci nad výpůjčkou výbavy.
void refreshGearBookings(WidgetRef ref, [String? bookingId]) {
  ref.invalidate(reservationsProvider);
  if (bookingId != null) {
    ref.invalidate(reservationByIdProvider(bookingId));
    ref.invalidate(gearDocsStatusProvider(bookingId));
  }
}

/// Stav dokladů KONKRÉTNÍ výpůjčky (`check_booking_docs_status_for`):
/// null = doklady OK, jinak důvod (server, česky). Chyba RPC = neznámo
/// (`'?'`) — UI pak ukáže obecnou výzvu jen u zadrženého kódu.
final gearDocsStatusProvider = FutureProvider.autoDispose.family<String?, String>((ref, bookingId) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('check_booking_docs_status_for', params: {'p_booking_id': bookingId})
        .timeout(const Duration(seconds: 15));
    if (res == null) return null;
    final s = '$res'.trim();
    return s.isEmpty ? null : s;
  } catch (_) {
    return '?';
  }
});
