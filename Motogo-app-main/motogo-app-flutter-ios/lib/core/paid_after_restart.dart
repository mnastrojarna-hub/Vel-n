import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'paid_change_queue.dart';
import 'payment_pending_marker.dart';
import 'supabase_client.dart';
import '../features/payment/paid_change_api.dart' show piIdFromClientSecret;
import '../features/payment/payment_verify.dart' show verifyPayment, VerifyState;

/// Platba odeslaná před zabitím / pádem appky — výsledek zjištěný po restartu
/// (AppShell ho jednou oznámí, viz `paidAfterRestartSnackBar`).
class PaidAfterRestart {
  final String bookingId;
  /// [PaymentMarkerKind] — určuje text oznámení (rezervace ≠ doplatek úpravy).
  final String kind;
  /// Zaplacenou výměnu / úpravu trvale nejde zapsat — typicky motorka je
  /// mezitím obsazená (nová rezervace má přednost) → doplatek se vrací.
  final bool failed;
  /// Doplatek prošel, zápis změny do rezervace ještě doběhne sám (fronta +
  /// server) → „dokončuje se", nikdy „uloženo".
  final bool completing;
  /// U [failed]: kód serveru, co se děje s doplatkem a kolik.
  final String? reason;
  final String refund;
  final double amount;
  const PaidAfterRestart(this.bookingId, this.kind,
      {this.failed = false, this.completing = false, this.reason, this.refund = 'auto', this.amount = 0});
}

/// Po startu appky: platba odeslaná před zabitím / pádem appky (lokální
/// značka) — výsledek ověřený podle DRUHU platby. Vrací rezervaci, jejíž
/// platba má mezitím známý výsledek (AppShell to jednou oznámí), jinak null.
/// Zrušené / neznámé značky uklidí.
///
/// Doplatek úpravy / výměny motorky běží nad UŽ ZAPLACENOU rezervací
/// (`payment_status` = 'paid' z původní platby) → rozhoduje fronta zaplacených
/// změn (D6), nová cena (úprava) nebo stav PaymentIntentu (výměna, SOS). Dokud
/// výsledek neznáme, značka zůstává (žádné falešné „zaplaceno", žádný druhý
/// doplatek).
final paidAfterRestartProvider =
    FutureProvider.autoDispose<PaidAfterRestart?>((ref) async {
  if (MotoGoSupabase.currentUser == null) return null;
  return PaidAfterRestartCheck.run();
});

class PaidAfterRestartCheck {
  PaidAfterRestartCheck._();

  /// Ověření platby podle značky — v testech nahraditelné.
  static Future<VerifyState> Function(PaymentMarker m) verify = _verify;

  static Future<VerifyState> _verify(PaymentMarker m) {
    final byTotal = m.kind == PaymentMarkerKind.edit && m.expectedTotal != null;
    return verifyPayment(
      bookingId: m.id,
      expectedTotal: byTotal ? m.expectedTotal : null,
      intentOnly: !byTotal,
    );
  }

  static Future<PaidAfterRestart?> run() async {
    final markers = await PaymentPendingMarker.pendingMarkers();
    // D6: zaplacený doplatek výměny / úpravy, jehož zápis appka nestihla (zabití
    // appky, výpadek sítě) → do trvalé fronty a dokončit přes server.
    for (final m in markers) {
      if (m.kind != PaymentMarkerKind.edit && m.kind != PaymentMarkerKind.swap) continue;
      final pi = piIdFromClientSecret(m.clientSecretCurrent ? m.clientSecret : null);
      if (pi == null || await PaidChangeQueue.get(pi) != null) continue;
      await PaidChangeQueue.enqueue(PaidChangeEntry(
          key: pi, bookingId: m.id, kind: m.kind == PaymentMarkerKind.swap ? 'swap' : 'edit',
          charge: 0, paid: false));
    }
    final done = <PaidChangeEntry>[];
    final failed = <PaidChangeEntry>[];
    final sub = PaidChangeQueue.events.listen((ev) {
      if (ev.result.status == PaidChangeStatus.done) done.add(ev.entry);
      // Trvalé selhání (motorka mezitím obsazená …) — doplatek se vrací. Tiše
      // smazaná nezaplacená pojistka (jiný účet / nedohledatelná) se neoznamuje.
      if (ev.result.status == PaidChangeStatus.failed && ev.entry.isFailed) failed.add(ev.entry);
    });
    try {
      await PaidChangeQueue.drain(reason: 'start', force: true);
      await Future<void>.delayed(Duration.zero); // doručit události z běhu
    } finally {
      await sub.cancel();
    }
    // Stav fronty po běhu: selhání z dřívějška (drain je přeskakuje) a změny,
    // které se teprve dokončují — u nich ověření platby NESMÍ hlásit „hotovo".
    final queued = await PaidChangeQueue.all();
    final markerIds = {for (final m in markers) m.id};
    for (final e in queued) {
      if (e.isFailed && markerIds.contains(e.bookingId) && !failed.any((f) => f.key == e.key)) failed.add(e);
    }
    for (final e in [...failed, ...done]) {
      await PaymentPendingMarker.clear(e.bookingId);
    }
    if (failed.isNotEmpty) {
      // Nejdřív selhání: zákazník musí vědět, že se změna nezapsala a doplatek
      // se vrací (stav PaymentIntentu je po vratce dál „succeeded" — ověření
      // platby by lhalo „výměnu dokončujeme").
      final f = failed.first;
      final x = f.failure ?? const {};
      return PaidAfterRestart(f.bookingId, f.isSwap ? PaymentMarkerKind.swap : PaymentMarkerKind.edit,
          failed: true,
          reason: x['reason']?.toString(),
          refund: '${x['refund'] ?? 'auto'}',
          amount: (x['amount'] as num?)?.toDouble() ?? f.charge);
    }
    if (done.isNotEmpty) {
      // Dokončeno teď → jednou oznámit (výměna motorky vlastním textem, ne
      // „úprava rezervace je uložená").
      final first = done.first;
      return PaidAfterRestart(
          first.bookingId, first.isSwap ? PaymentMarkerKind.swap : PaymentMarkerKind.edit);
    }
    final completing = {for (final e in queued) if (!e.isFailed) e.bookingId};
    for (final m in markers) {
      try {
        switch (m.kind) {
          case PaymentMarkerKind.order:
            continue; // objednávku e-shopu ověřuje košík / „Platba se ověřuje"
          case PaymentMarkerKind.edit:
          case PaymentMarkerKind.swap:
          case PaymentMarkerKind.sos:
            if (await verify(m) != VerifyState.paid) continue;
            // Zaplaceno, ale zápis změny ve frontě ještě běží → „dokončuje se".
            return PaidAfterRestart(m.id, m.kind,
                completing: m.kind != PaymentMarkerKind.sos && completing.contains(m.id));
          default:
            final row = await MotoGoSupabase.client
                .from('bookings')
                .select('status, payment_status')
                .eq('id', m.id)
                .maybeSingle()
                .timeout(const Duration(seconds: 10));
            if (row == null) continue; // cizí id — nechat doběhnout
            if (row['payment_status'] == 'paid') {
              await PaymentPendingMarker.clear(m.id);
              return PaidAfterRestart(m.id, PaymentMarkerKind.booking);
            }
            if (row['status'] == 'cancelled') await PaymentPendingMarker.clear(m.id);
        }
      } catch (_) {/* offline — zkusí se při dalším startu */}
    }
    return null;
  }
}
