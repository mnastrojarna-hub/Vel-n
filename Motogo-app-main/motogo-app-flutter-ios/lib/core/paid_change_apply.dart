import 'package:flutter/foundation.dart';

import 'paid_change_entry.dart';
import 'supabase_client.dart';
import '../features/payment/paid_change_api.dart';
import '../features/reservations/booking_extras_sync.dart'
    show deleteExtrasRowsByIds, extraIdFromExtrasName, stripInternalKeys;

/// Jeden pokus o dokončení zaplacené změny (D6). Server (`complete_extension`)
/// je zdroj pravdy a je idempotentní; appka dopisuje jen to, co server nezná
/// (doplňky `booking_extras`, stará klientská cesta). Nikdy nehází.
class PaidChangeApply {
  PaidChangeApply._();

  /// Volání serveru — v testech nahraditelné.
  static Future<CompleteResponse> Function(String piId, Duration timeout) complete =
      (piId, timeout) => completeExtension(piId, timeout: timeout);

  /// Doplňky po zápisu změny — v testech nahraditelné. true = hotovo.
  static Future<bool> Function(String bookingId, Map<String, dynamic> extras) applyExtras =
      applyExtrasOnce;

  /// Stará klientská cesta (změna se nevešla do metadat) — v testech nahraditelné.
  static Future<bool> Function(PaidChangeEntry e) clientApply = _clientApply;

  static Future<PaidChangeResult> attempt(PaidChangeEntry e, {Duration timeout = const Duration(seconds: 20)}) async {
    var serverDone = e.state == 'extras';
    String? newBookingId;
    if (!serverDone) {
      final r = await complete(e.key, timeout);
      switch (r.state) {
        case CompleteState.applied:
          serverDone = true;
          newBookingId = r.newBookingId;
        case CompleteState.clientApply:
          if (!await _safe(() => clientApply(e))) {
            return const PaidChangeResult(PaidChangeStatus.completing);
          }
          serverDone = true;
        case CompleteState.failed:
          return PaidChangeResult(PaidChangeStatus.failed,
              reason: r.reason, refund: r.refund, amount: r.amount ?? e.charge);
        case CompleteState.notPaid:
          return const PaidChangeResult(PaidChangeStatus.notPaid);
        case CompleteState.pending:
        case CompleteState.retry:
          return PaidChangeResult(PaidChangeStatus.completing, offline: r.offline);
      }
    }
    final x = e.extras;
    if (serverDone && x != null && !await _safe(() => applyExtras(e.bookingId, x))) {
      // Změna je zapsaná, chybí jen doplňky → příště jen ty (stav 'extras').
      return const PaidChangeResult(PaidChangeStatus.completing, reason: 'extras');
    }
    return PaidChangeResult(PaidChangeStatus.done, newBookingId: newBookingId);
  }

  static Future<bool> _safe(Future<bool> Function() f) async {
    try {
      return await f();
    } catch (err) {
      debugPrint('[PaidChange] apply step failed: $err');
      return false;
    }
  }

  /// Stará cesta: sloupce úpravy zapíše klient (server neměl payload). Nikdy
  /// nezapisuje `total_price`, když se dorovnávalo (cenu drží server).
  static Future<bool> _clientApply(PaidChangeEntry e) async {
    final sw = e.swap;
    if (sw != null) {
      final res = await MotoGoSupabase.client
          .rpc('split_booking_moto_swap', params: {...sw, 'p_dry_run': false})
          .timeout(const Duration(seconds: 20));
      final code = res is Map ? res['error']?.toString() : null;
      return (res is Map && res['success'] == true) || code == 'already_split' || code == 'invalid_new_moto';
    }
    final cols = e.columns;
    if (cols == null || cols.isEmpty) return true;
    await MotoGoSupabase.client
        .from('bookings')
        .update(stripInternalKeys(cols))
        .eq('id', e.bookingId)
        .timeout(const Duration(seconds: 20));
    return true;
  }
}

/// Idempotentní náhrada modelovaných doplňků (bezpečná i při opakování po
/// pádu appky): smaže původní řádky, které ještě existují a nový stav je
/// nemá, a vloží jen doplňky, které v rezervaci ještě nejsou — nic se
/// nezdvojí, i když předchozí pokus spadl po vložení.
Future<bool> applyExtrasOnce(String bookingId, Map<String, dynamic> extras) async {
  final rows = (extras['rows'] as List?) ?? const [];
  final origIds = ((extras['del'] as List?) ?? const []).map((e) => '$e').toList();
  final cur = await MotoGoSupabase.client
      .from('booking_extras')
      .select('id, name')
      .eq('booking_id', bookingId)
      .timeout(const Duration(seconds: 15));
  final curRows = [for (final r in cur as List) if (r is Map) r];
  final left = [for (final id in origIds) if (curRows.any((r) => '${r['id']}' == id)) id];
  var deleted = 0;
  if (left.isNotEmpty) {
    try {
      deleted = await deleteExtrasRowsByIds(bookingId, left).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[PaidChange] extras delete failed: $e');
    }
  }
  final full = deleted >= left.length;
  // Doplňky, které v rezervaci po smazání zůstaly (nesmazané původní + už vložené).
  final present = <String>{};
  for (final r in curRows) {
    if (full && left.contains('${r['id']}')) continue;
    final id = extraIdFromExtrasName('${r['name'] ?? ''}');
    if (id != null) present.add(id);
  }
  final toInsert = <Map<String, dynamic>>[
    for (final r in rows)
      if (r is Map && !present.contains(r['_extra'])) stripInternalKeys(r),
  ];
  if (toInsert.isNotEmpty) {
    await MotoGoSupabase.client.from('booking_extras').insert(toInsert).timeout(const Duration(seconds: 15));
  }
  return true;
}
