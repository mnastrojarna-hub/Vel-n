import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lokální značka „platba odeslána, výsledek zatím neznáme" (2026-10-16).
///
/// Proč: když Stripe platbu přijal, ale server (webhook) ji ještě nepotvrdil,
/// nebo se po stržení uložené karty ztratila odpověď, je rezervace v DB pořád
/// `unpaid` — a FAB „Dokončit rezervaci" by zákazníkovi nabídl zaplatit
/// ZNOVU (dvojí platba). Dokud je značka čerstvá (< [paymentMarkerTtl]) a DB
/// platbu nepotvrdila, appka ukazuje „Platba se ověřuje" místo další platby.
///
/// Klíč = id rezervace nebo objednávky; hodnota = čas odeslání (ms) +
/// volitelně client secret PaymentIntentu (jen pro ověření stavu u Stripe na
/// tomtéž zařízení, po [paymentMarkerTtl] se maže). Chyba úložiště nesmí
/// platbu shodit — značka je jen pojistka, každá operace je v try/catch.
const paymentMarkerTtl = Duration(minutes: 15);

class PaymentMarker {
  final String id;
  final DateTime at;
  final String? clientSecret;
  const PaymentMarker(this.id, this.at, this.clientSecret);
}

class PaymentPendingMarker {
  PaymentPendingMarker._();

  static const _key = 'mg_payment_submitted_v2';

  static Map<String, Map<String, dynamic>> _load(SharedPreferences p) {
    try {
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final m = <String, Map<String, dynamic>>{};
      (jsonDecode(raw) as Map).forEach((k, v) {
        if (v is Map) m[k.toString()] = Map<String, dynamic>.from(v);
      });
      final now = DateTime.now().millisecondsSinceEpoch;
      m.removeWhere((_, v) =>
          now - ((v['at'] as num?)?.toInt() ?? 0) > paymentMarkerTtl.inMilliseconds);
      return m;
    } catch (_) {
      return {};
    }
  }

  /// Platba pro [id] byla odeslána (nebo její výsledek je nejistý).
  /// [clientSecret] = PaymentIntent, je-li znám (ověření stavu u Stripe).
  static Future<void> set(String? id, {String? clientSecret}) async {
    if (id == null || id.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final m = _load(p);
      final prev = m[id];
      m[id] = {
        'at': DateTime.now().millisecondsSinceEpoch,
        if ((clientSecret ?? prev?['cs']) != null) 'cs': clientSecret ?? prev?['cs'],
      };
      await p.setString(_key, jsonEncode(m));
    } catch (_) {}
  }

  /// Výsledek je známý (zaplaceno / prokazatelně nestrženo) → značku smazat.
  static Future<void> clear(String? id) async {
    if (id == null || id.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final m = _load(p);
      if (m.remove(id) != null) await p.setString(_key, jsonEncode(m));
    } catch (_) {}
  }

  /// Čerstvá značka pro [id], jinak null.
  static Future<PaymentMarker?> get(String? id) async {
    if (id == null || id.isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final v = _load(p)[id];
      if (v == null) return null;
      return PaymentMarker(
          id,
          DateTime.fromMillisecondsSinceEpoch((v['at'] as num).toInt()),
          v['cs'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// true = platba pro [id] byla odeslána před méně než [paymentMarkerTtl].
  static Future<bool> isPending(String? id) async => (await get(id)) != null;

  /// Všechna čerstvá id (kontrola výsledku po restartu appky).
  static Future<List<String>> pendingIds() async {
    try {
      final p = await SharedPreferences.getInstance();
      return _load(p).keys.toList();
    } catch (_) {
      return const [];
    }
  }
}
