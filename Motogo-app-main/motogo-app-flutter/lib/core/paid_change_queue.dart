import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'paid_change_apply.dart';
import 'paid_change_entry.dart';

export 'paid_change_entry.dart';

/// Trvalá fronta zaplacených výměn motorky / úprav rezervace (D6, rozhodnutí
/// majitele 2026-10-16: „musí se povést uložit; když ne hned, tak za chvíli,
/// třeba po obnovení internetu").
///
/// Zaplacenou změnu dokončuje primárně server (webhook Stripe, opakuje až 3 dny)
/// a appka mu pomáhá: položku zapíše hned po zaplacení (přežije zabití appky),
/// zkouší `complete_extension` při startu appky, po návratu připojení, při
/// návratu do popředí a s rostoucí prodlevou (10 s → 10 min), dokud server
/// zápis nepotvrdí. Server je idempotentní, takže souběh s webhookem nevadí.
/// Zákazník mezitím vidí „Výměna se dokončuje", nikdy chybu.
class PaidChangeQueue {
  PaidChangeQueue._();

  static const storeKey = 'mg_paid_change_queue_v1';
  /// Zaplacená změna, kterou server ani po téhle době nepotvrdil (a appka je
  /// online), se zákazníkovi jednou ukáže jako „kontroluje obsluha" (server
  /// webhook ji po ~70 h předává obsluze sám) — nikdy tiché zmizení.
  static const maxAge = Duration(days: 7);
  /// Pojistka zapsaná při odeslání platby (nezaplaceno) — po téhle době platba
  /// prokazatelně nedoběhla (3D Secure nedokončené / opuštěné) → smazat.
  static const unpaidMaxAge = Duration(hours: 24);
  /// Úplná horní mez (offline měsíc, chyba bez potvrzení zákazníkem).
  static const hardMaxAge = Duration(days: 45);
  /// Prodleva po n-tém neúspěšném pokusu.
  static const backoff = [
    Duration(seconds: 10), Duration(seconds: 30), Duration(minutes: 1),
    Duration(minutes: 2), Duration(minutes: 5), Duration(minutes: 10),
  ];

  /// Hodiny (testy) a samočinné plánování časovače (testy vypínají).
  static DateTime Function() clock = DateTime.now;
  static bool autoSchedule = true;

  static final _events = StreamController<PaidChangeEvent>.broadcast();
  static Stream<PaidChangeEvent> get events => _events.stream;

  static Future<void> _lock = Future.value();
  static Future<void>? _draining;
  static final _inflight = <String, Future<PaidChangeResult>>{};
  static Timer? _timer;

  static int get _now => clock().millisecondsSinceEpoch;

  static Duration delayFor(int attempts) =>
      backoff[(attempts - 1).clamp(0, backoff.length - 1)];

  // ── úložiště ─────────────────────────────────────────────────────────────
  static Future<Map<String, PaidChangeEntry>> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(storeKey);
      if (raw == null || raw.isEmpty) return {};
      final out = <String, PaidChangeEntry>{};
      (jsonDecode(raw) as Map).forEach((k, v) {
        final e = PaidChangeEntry.fromJson(v);
        if (e != null && !_expired(e)) out[e.key] = e;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, PaidChangeEntry> m) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(storeKey, jsonEncode({for (final e in m.values) e.key: e.toJson()}));
    } catch (_) {}
  }

  /// Čtení-úprava-zápis jedno po druhém (žádná ztracená změna při souběhu).
  static Future<T> _mutate<T>(T Function(Map<String, PaidChangeEntry> m) fn) {
    final c = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        final m = await _load();
        final r = fn(m);
        await _save(m);
        c.complete(r);
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  // ── veřejné API ──────────────────────────────────────────────────────────
  /// Zapíše (nebo aktualizuje) položku — idempotentně podle klíče. Pokusy a
  /// stav existující položky zůstávají; `paid` se jen zapíná. [delay] = první
  /// pokus až po prodlevě (zápis při odeslání platby, ať se server neptá
  /// uprostřed 3D Secure).
  static Future<void> enqueue(PaidChangeEntry e, {Duration delay = Duration.zero}) async {
    if (e.key.isEmpty || e.bookingId.isEmpty) return;
    await _mutate((m) {
      final old = m[e.key];
      m[e.key] = old == null
          ? e.copyWith(createdAt: _now, nextAt: _now + delay.inMilliseconds)
          : old.copyWith(paid: old.paid || e.paid, nextAt: e.paid ? _now : old.nextAt);
    });
    _schedule();
  }

  static Future<PaidChangeEntry?> get(String key) async => (await _load())[key];

  static Future<List<PaidChangeEntry>> all() async => (await _load()).values.toList();

  /// Zaplacené položky rezervace (banner „dokončuje se" / jednorázová chyba).
  static Future<List<PaidChangeEntry>> forBooking(String bookingId) async =>
      [for (final e in (await _load()).values) if (e.bookingId == bookingId && e.paid) e];

  /// Platba prokazatelně neproběhla → pojistnou (nezaplacenou) položku smazat.
  static Future<void> discard(String? key) async {
    if (key == null) return;
    await _mutate((m) {
      if (m[key]?.paid == false) m.remove(key);
    });
  }

  /// Chybu zákazník viděl → položku smazat.
  static Future<void> acknowledge(String key) => _mutate((m) => m.remove(key));

  /// Jeden pokus hned (popředí: platební obrazovka, „Ověřit znovu").
  static Future<PaidChangeResult> completeNow(String key,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final e = (await _load())[key];
    if (e == null) {
      // Položka už je pryč (dokončila ji jiná cesta) → zeptat se serveru.
      final r = await PaidChangeApply.attempt(
          PaidChangeEntry(key: key, bookingId: '-', kind: 'edit', charge: 0),
          timeout: timeout);
      return r;
    }
    if (e.isFailed) {
      return PaidChangeResult(PaidChangeStatus.failed,
          reason: e.failure?['reason']?.toString(),
          refund: '${e.failure?['refund'] ?? 'auto'}',
          amount: (e.failure?['amount'] as num?)?.toDouble() ?? e.charge);
    }
    return _attemptKey(e, timeout);
  }

  /// Projde všechny položky, jejichž čas nastal (start appky, připojení zpět,
  /// popředí, časovač). Jen jeden běh najednou.
  static Future<void> drain({String reason = 'manual', bool force = false}) {
    return _draining ??= _drainImpl(reason, force).whenComplete(() {
      _draining = null;
      _schedule();
    });
  }

  static Future<void> _drainImpl(String reason, bool force) async {
    final due = [
      for (final e in (await _load()).values)
        if (!e.isFailed && (force || e.nextAt <= _now)) e,
    ];
    if (due.isNotEmpty) debugPrint('[PaidChange] drain ($reason): ${due.length}');
    for (final e in due) {
      await _attemptKey(e, const Duration(seconds: 20));
    }
  }

  /// Pokus pro jeden klíč — souběžné volání téhož klíče se sloučí (doplňky se
  /// nesmí vložit dvakrát).
  static Future<PaidChangeResult> _attemptKey(PaidChangeEntry e, Duration timeout) {
    return _inflight[e.key] ??= () async {
      try {
        final r = await PaidChangeApply.attempt(e, timeout: timeout);
        await _record(e, r);
        return r;
      } finally {
        _inflight.remove(e.key);
      }
    }();
  }

  static Future<void> _record(PaidChangeEntry e, PaidChangeResult r) async {
    final stored = await _mutate<PaidChangeEntry?>((m) {
      final cur = m[e.key];
      if (cur == null) return null;
      switch (r.status) {
        case PaidChangeStatus.done:
        case PaidChangeStatus.notPaid:
          m.remove(e.key);
          return cur;
        case PaidChangeStatus.failed:
          return m[e.key] = cur.copyWith(state: 'failed', failure: {
            'reason': r.reason,
            'refund': r.refund,
            'amount': r.amount ?? cur.charge,
          });
        case PaidChangeStatus.completing:
          final n = cur.attempts + 1;
          return m[e.key] = cur.copyWith(
              attempts: n,
              nextAt: _now + delayFor(n).inMilliseconds,
              state: r.reason == 'extras' ? 'extras' : cur.state);
      }
    });
    if (stored != null) _events.add(PaidChangeEvent(stored, r));
  }

  /// Jeden časovač na nejbližší pokus (dokud appka běží).
  static void _schedule() {
    if (!autoSchedule) return;
    unawaited(() async {
      final pending = [for (final e in (await _load()).values) if (!e.isFailed) e.nextAt];
      _timer?.cancel();
      _timer = null;
      if (pending.isEmpty) return;
      pending.sort();
      final wait = Duration(milliseconds: (pending.first - _now).clamp(1000, 600000));
      _timer = Timer(wait, () => drain(reason: 'timer'));
    }());
  }

  /// Jen testy: vyčistí stav v paměti.
  @visibleForTesting
  static void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _draining = null;
    _inflight.clear();
    _lock = Future.value();
  }
}
