import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException, PostgrestException;

import '../../core/supabase_client.dart';

/// Nová serverová API záznamu jízd (pauzy, cesty) + rozlišení „server to
/// ještě neumí" od „jsem offline". Nová appka musí fungovat i proti
/// STARÉMU serveru (SQL ještě nenasazené) — pak se vrací ke starým RPC.

/// Proč volání selhalo.
///   missing – server funkci / sloupec nezná (starý server) → fallback
///   offline – síť / timeout → zkusit znovu, NIKDY ne fallback
///   error   – jiná chyba serveru → zkusit znovu
enum RideRpcErrorKind { missing, offline, error }

RideRpcErrorKind classifyRideRpcError(Object e) {
  if (e is PostgrestException) {
    final c = e.code ?? '';
    if (c == 'PGRST202' || c == '42883' || c == '42703' || c == '404') {
      return RideRpcErrorKind.missing;
    }
    return RideRpcErrorKind.error;
  }
  if (e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException ||
      e is AuthRetryableFetchException) {
    return RideRpcErrorKind.offline;
  }
  return RideRpcErrorKind.error;
}

/// Posun hodin telefonu vůči serveru (s): `server − (t0+t1)/2`; do ±120 s
/// se neřeší (0 = dnešní chování).
double rideClockOffset(double serverNow, DateTime t0, DateTime t1) {
  final mid = (t0.millisecondsSinceEpoch + t1.millisecondsSinceEpoch) / 2000;
  final off = serverNow - mid;
  return off.abs() <= 120 ? 0 : (off * 10).round() / 10;
}

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int? _i(Object? v) => _d(v)?.round();

/// Výsledek odeslání dávky bodů.
///   ok     – uloženo, dávku zahodit
///   retry  – výpadek sítě / serveru, body si necháme na příště
///   closed – server jízdu uzavřel (`ride_finished`: úklid, konec výpůjčky)
///   gone   – server jízdu nezná (`ride_not_found`: smazaná)
enum RideAppendResult { ok, retry, closed, gone }

class RideAppendOutcome {
  const RideAppendOutcome(this.result,
      {this.distanceKm, this.movingSec, this.pauseSec, this.stagesN, this.serverNow, this.bookingEnded = false});

  final RideAppendResult result;
  final double? distanceKm;
  final int? movingSec;
  final int? pauseSec;
  final int? stagesN;
  /// `now` serveru (jen nový server) — pro posun hodin.
  final double? serverNow;
  /// Server uzavřel jízdu, protože výpůjčka skončila (nový server).
  final bool bookingEnded;

  static const retry = RideAppendOutcome(RideAppendResult.retry);

  /// Odpověď `append_ride_track` (starý i nový server).
  static RideAppendOutcome fromResponse(Object? res) {
    if (res is! Map) return retry;
    if (res['success'] == true) {
      return RideAppendOutcome(
        RideAppendResult.ok,
        distanceKm: _d(res['distance_km']),
        movingSec: _i(res['moving_sec']),
        pauseSec: _i(res['pause_sec']),
        stagesN: _i(res['stages_n']),
        serverNow: _d(res['now']),
      );
    }
    final err = res['error']?.toString();
    if (err == 'ride_finished') {
      return RideAppendOutcome(RideAppendResult.closed, bookingEnded: res['reason'] == 'booking_ended');
    }
    if (err == 'ride_not_found') return const RideAppendOutcome(RideAppendResult.gone);
    return retry;
  }
}

/// Výsledek `start_user_trip`.
enum RideTripStartKind { ok, missing, bookingInactive, notAuthenticated, offline, error }

class RideTripStart {
  const RideTripStart(this.kind,
      {this.id,
      this.resumed = false,
      this.bookingId,
      this.motoName,
      this.startedAt,
      this.distanceKm = 0,
      this.movingSec = 0,
      this.pauseSec = 0,
      this.stagesN = 0,
      this.clockOffset = 0,
      this.serverNow});

  final RideTripStartKind kind;
  final String? id;
  final bool resumed;
  final String? bookingId;
  final String? motoName;
  final DateTime? startedAt;
  final double distanceKm;
  final int movingSec;
  final int pauseSec;
  final int stagesN;
  /// Posun hodin telefonu (s), viz [rideClockOffset].
  final double clockOffset;
  final double? serverNow;

  bool get ok => kind == RideTripStartKind.ok && id != null;
}

/// Zahájí / obnoví záznam cesty (nový server). Nová jízda začíná
/// „připravená" — server ji posune na skutečný rozjezd (značka −1).
Future<RideTripStart> startUserTrip(String? bookingId) =>
    _startTripRpc('start_user_trip', {'p_booking_id': bookingId});

/// Jako [startUserTrip] pro relaci, která začala BEZ dat (start offline —
/// zahraničí bez roamingu): nová jízda začne [firstTs] (první bod relace,
/// epoch s), ne až teď — body z doby offline server nezahodí jako „starou
/// jízdu". U výpůjčky vrácené dřív, než se jízdu podařilo založit, ji
/// server založí zpětně (body do vrácení uloží, po něm zahodí). Starý server
/// funkci nezná → `missing` → záznamník zavolá [startUserTrip].
Future<RideTripStart> startUserTripFrom(String? bookingId, double firstTs) => _startTripRpc(
    'start_user_trip_from', {'p_booking_id': bookingId, 'p_first_ts': (firstTs * 1000).round() / 1000});

Future<RideTripStart> _startTripRpc(String fn, Map<String, dynamic> params) async {
  final t0 = DateTime.now();
  try {
    final res = await MotoGoSupabase.client.rpc(fn, params: params).timeout(const Duration(seconds: 20));
    final t1 = DateTime.now();
    if (res is! Map) return const RideTripStart(RideTripStartKind.error);
    final now = _d(res['now']);
    final off = now == null ? 0.0 : rideClockOffset(now, t0, t1);
    if (res['success'] != true) {
      final err = res['error']?.toString();
      return RideTripStart(switch (err) {
        'booking_inactive' => RideTripStartKind.bookingInactive,
        'not_authenticated' => RideTripStartKind.notAuthenticated,
        _ => RideTripStartKind.error,
      }, serverNow: now, clockOffset: off);
    }
    final id = res['id']?.toString();
    if (id == null || id.isEmpty) return const RideTripStart(RideTripStartKind.error);
    return RideTripStart(
      RideTripStartKind.ok,
      id: id,
      resumed: res['resumed'] == true,
      bookingId: res['booking_id']?.toString(),
      motoName: res['moto_name']?.toString(),
      startedAt: DateTime.tryParse(res['started_at']?.toString() ?? ''),
      distanceKm: _d(res['distance_km']) ?? 0,
      movingSec: _i(res['moving_sec']) ?? 0,
      pauseSec: _i(res['pause_sec']) ?? 0,
      stagesN: _i(res['stages_n']) ?? 0,
      clockOffset: off,
      serverNow: now,
    );
  } catch (e) {
    debugPrint('[rides] $fn selhalo: $e');
    return RideTripStart(switch (classifyRideRpcError(e)) {
      RideRpcErrorKind.missing => RideTripStartKind.missing,
      RideRpcErrorKind.offline => RideTripStartKind.offline,
      RideRpcErrorKind.error => RideTripStartKind.error,
    });
  }
}

/// Zná server pauzy a cesty (sloupec `user_rides.pause_aware`)? true / false,
/// null = nevíme (offline) → platí poslední známá hodnota.
Future<bool?> probeRideServerV2() async {
  try {
    await MotoGoSupabase.client
        .from('user_rides')
        .select('pause_aware')
        .limit(1)
        .timeout(const Duration(seconds: 10));
    return true;
  } catch (e) {
    return switch (classifyRideRpcError(e)) {
      RideRpcErrorKind.missing => false,
      _ => null,
    };
  }
}

/// Skončila výpůjčka (vrácená, dokončená — i SOS výměnou —, zrušená)?
/// Záznam stojící v auto-pauze se tak dozví o vrácení bez otevření appky.
/// Noc v boxu samoobsluhy (výpůjčka běží dál) = false. null = nevíme
/// (offline, řádek nevidí) → nic se nerozhoduje. Stejné na starém i novém
/// serveru (čte se `bookings` jako seznam rezervací).
Future<bool?> rideRentalEnded(String bookingId) async {
  try {
    final row = await MotoGoSupabase.client
        .from('bookings')
        .select('status, returned_at')
        .eq('id', bookingId)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    if (row == null) return null;
    final st = '${row['status'] ?? ''}';
    return row['returned_at'] != null || st == 'completed' || st == 'cancelled';
  } catch (e) {
    debugPrint('[rides] stav výpůjčky selhal: $e');
    return null;
  }
}

/// Jízdu výpůjčky [rideId] uzavřel server sám (`closed_by` return / cron /
/// start — zaparkování v kóji kiosku, úklid), ne jezdec ani obsluha → čas
/// konce, jinak null. Výpůjčka přitom může dál běžit (kóje před posledním
/// dnem = „zaparkováno", dokončí ji až noční zpracování). Starý server
/// (sloupec `stats_state` neexistuje), offline, smazaná jízda → null.
Future<DateTime?> rideRentalRideClosedAt(String rideId) async {
  try {
    final row = await MotoGoSupabase.client
        .from('user_rides')
        .select('is_recording, ended_at, closed_by:stats_state->>closed_by')
        .eq('id', rideId)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    if (row == null || row['is_recording'] != false) return null;
    if (!const {'return', 'cron', 'start'}.contains('${row['closed_by'] ?? ''}')) return null;
    return DateTime.tryParse('${row['ended_at'] ?? ''}');
  } catch (e) {
    debugPrint('[rides] stav jízdy výpůjčky selhal: $e');
    return null;
  }
}

/// Jedna položka pro `set_user_rides_trip`: `tripId == id` = samostatná
/// jízda, null = výchozí seskupení (podle výpůjčky), jiné = člen cesty.
class RideTripItem {
  const RideTripItem(this.id, this.tripId, this.tripName);
  final String id;
  final String? tripId;
  final String? tripName;

  Map<String, dynamic> toJson() => {'id': id, 'trip_id': tripId, 'trip_name': tripName};
}

enum RideTripSetKind { ok, missing, offline, error }

class RideTripSetResult {
  const RideTripSetResult(this.kind, {this.updated = 0});
  final RideTripSetKind kind;
  final int updated;
}

/// Hromadné nastavení příslušnosti jízd k cestám (sloučit / rozdělit /
/// přejmenovat / zpět). Cizí a neexistující id server tiše přeskočí —
/// [RideTripSetResult.updated] se porovná s počtem odeslaných.
Future<RideTripSetResult> setUserRidesTrip(List<RideTripItem> items) async {
  if (items.isEmpty) return const RideTripSetResult(RideTripSetKind.ok);
  try {
    final res = await MotoGoSupabase.client.rpc('set_user_rides_trip', params: {
      'p_items': [for (final i in items) i.toJson()],
    }).timeout(const Duration(seconds: 20));
    if (res is Map && res['success'] == true) {
      return RideTripSetResult(RideTripSetKind.ok, updated: _i(res['updated']) ?? 0);
    }
    return const RideTripSetResult(RideTripSetKind.error);
  } catch (e) {
    debugPrint('[rides] set_user_rides_trip selhalo: $e');
    return RideTripSetResult(switch (classifyRideRpcError(e)) {
      RideRpcErrorKind.missing => RideTripSetKind.missing,
      RideRpcErrorKind.offline => RideTripSetKind.offline,
      RideRpcErrorKind.error => RideTripSetKind.error,
    });
  }
}
