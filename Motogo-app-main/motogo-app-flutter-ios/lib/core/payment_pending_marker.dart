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

/// Jak dlouho po vypršení [paymentMarkerTtl] ještě pamatovat PaymentIntent
/// posledního pokusu: banka může platbu potvrzovat déle než 15 minut — FAB
/// pak před nabídkou další platby ověří stav u Stripe (dvojí platba).
const paymentIntentKeep = Duration(hours: 2);

/// Co se platí — rozhoduje, čím se po restartu appky ověří výsledek.
/// Doplatek úpravy / výměny běží nad UŽ ZAPLACENOU rezervací (`payment_status`
/// = 'paid' z původní platby) → „zaplaceno" podle DB by byl falešný úspěch.
class PaymentMarkerKind {
  PaymentMarkerKind._();
  /// Nová / dokončovaná / obnovená rezervace — důkaz = `payment_status`.
  static const booking = 'booking';
  /// Doplatek úpravy rezervace — důkaz = nová `total_price` ([PaymentMarker.expectedTotal]).
  static const edit = 'edit';
  /// Doplatek výměny motorky — důkaz jen stav PaymentIntentu u Stripe.
  static const swap = 'swap';
  /// Platba SOS nad existující rezervací — důkaz jen stav PaymentIntentu.
  static const sos = 'sos';
  /// Objednávka e-shopu (ověřuje si ji košík sám).
  static const order = 'order';
}

class PaymentMarker {
  final String id;
  final DateTime at;
  final String? clientSecret;
  /// [clientSecret] patří k POSLEDNÍMU pokusu o platbu (zapsal ho právě ten
  /// pokus). Jen takový PaymentIntent smí rozhodnout „nezaplaceno" — starý,
  /// opuštěný intent z dřívějšího pokusu by lhal (dvojí platba).
  final bool clientSecretCurrent;
  /// [PaymentMarkerKind] — bez údaje (starší zápis) = rezervace.
  final String kind;
  /// Doplatek úpravy: nová cena rezervace po zaplacení (důkaz v DB).
  final double? expectedTotal;
  const PaymentMarker(this.id, this.at, this.clientSecret,
      {this.clientSecretCurrent = false,
      this.kind = PaymentMarkerKind.booking,
      this.expectedTotal});
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
      m.removeWhere((_, v) {
        final age = now - ((v['at'] as num?)?.toInt() ?? 0);
        return age > (_hasCurrentCs(v) ? paymentIntentKeep : paymentMarkerTtl).inMilliseconds;
      });
      return m;
    } catch (_) {
      return {};
    }
  }

  static bool _hasCurrentCs(Map<String, dynamic> v) {
    final att = (v['att'] as num?)?.toInt();
    return v['cs'] != null && att != null && (v['csAtt'] as num?)?.toInt() == att;
  }

  static bool _fresh(Map<String, dynamic> v) =>
      DateTime.now().millisecondsSinceEpoch - ((v['at'] as num?)?.toInt() ?? 0) <=
      paymentMarkerTtl.inMilliseconds;

  /// Platba pro [id] byla odeslána (nebo její výsledek je nejistý).
  /// [clientSecret] = PaymentIntent TOHOTO pokusu, je-li znám (ověření stavu
  /// u Stripe). [fresh] = začíná nový pokus o platbu: PaymentIntent z
  /// dřívějšího pokusu se NEDĚDÍ (opuštěný nezaplacený intent by jinak při
  /// ověření tvrdil „nic nestrženo", i když právě stržená uložená karta prošla).
  /// [kind] = [PaymentMarkerKind] (doplatek úpravy / výměny se po restartu
  /// NESMÍ ověřovat podle `payment_status`), [expectedTotal] = nová cena
  /// rezervace po doplatku úpravy.
  static Future<void> set(String? id,
      {String? clientSecret,
      bool fresh = false,
      String? kind,
      double? expectedTotal}) async {
    if (id == null || id.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final m = _load(p);
      final old = m[id];
      final prev = fresh ? null : old;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Číslo pokusu (čas jeho začátku) — nový pokus = nové číslo.
      final att = (prev?['att'] as num?)?.toInt() ?? now;
      final cs = clientSecret ?? prev?['cs'];
      final csAtt = clientSecret != null ? att : prev?['csAtt'];
      final k = kind ?? old?['k'];
      final exp = expectedTotal ?? prev?['exp'];
      m[id] = {
        'at': now,
        'att': att,
        if (cs != null) 'cs': cs,
        if (cs != null && csAtt != null) 'csAtt': csAtt,
        if (k != null) 'k': k,
        if (exp != null) 'exp': exp,
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
      if (v == null || !_fresh(v)) return null;
      return _marker(id, v);
    } catch (_) {
      return null;
    }
  }

  static PaymentMarker _marker(String id, Map<String, dynamic> v) {
    final att = (v['att'] as num?)?.toInt();
    return PaymentMarker(
        id,
        DateTime.fromMillisecondsSinceEpoch((v['at'] as num).toInt()),
        v['cs'] as String?,
        clientSecretCurrent: att != null && (v['csAtt'] as num?)?.toInt() == att,
        kind: (v['k'] as String?) ?? PaymentMarkerKind.booking,
        expectedTotal: (v['exp'] as num?)?.toDouble());
  }

  /// true = platba pro [id] byla odeslána před méně než [paymentMarkerTtl].
  static Future<bool> isPending(String? id) async => (await get(id)) != null;

  /// Všechny čerstvé značky (kontrola výsledku po restartu appky).
  static Future<List<PaymentMarker>> pendingMarkers() async {
    try {
      final p = await SharedPreferences.getInstance();
      return _load(p)
          .entries
          .where((e) => _fresh(e.value))
          .map((e) => _marker(e.key, e.value))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Id všech čerstvých značek.
  static Future<List<String>> pendingIds() async =>
      [for (final m in await pendingMarkers()) m.id];

  /// PaymentIntent posledního pokusu, jehož značka už vypršela (> 15 min),
  /// ale intent si pamatujeme ([paymentIntentKeep]) — před nabídkou další
  /// platby ověřit jeho stav u Stripe. null = nic takového.
  static Future<String?> expiredIntent(String? id) async {
    if (id == null || id.isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final v = _load(p)[id];
      if (v == null || _fresh(v) || !_hasCurrentCs(v)) return null;
      return v['cs'] as String?;
    } catch (_) {
      return null;
    }
  }
}
