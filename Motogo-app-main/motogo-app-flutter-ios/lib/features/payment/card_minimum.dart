import 'dart:math';

/// Minimální platba kartou (D1/D2, rozhodnutí majitele 2026-10-16).
///
/// Stripe neumí v CZK strhnout méně než 15 Kč. Pravidlo (shodné se serverem,
/// `process-payment/card-minimum.ts`):
///   due ≤ 0          → zdarma (stávající cesty),
///   0 < due ≤ 1 Kč   → NEÚČTUJE SE (nic se nestrhne, server částku odpustí),
///   1 < due < 15 Kč  → zaplatí se 15 Kč (dorovnání 15 − due, na dokladu řádek),
///   due ≥ 15 Kč      → beze změny.
/// Appka posílá `card_min: true` — server pak dorovná / odpustí jen tehdy, když
/// ho appka o to výslovně požádá (částka 15 / 0). Dorovnání zapisuje SERVER
/// (`card_rounding`), appka ho jen ukazuje.
const cardMinCzk = 15;

/// Do této částky (včetně) se zbytek k zaplacení neúčtuje.
const cardWaiveMaxCzk = 1;

enum CardChargeKind {
  /// Nic k zaplacení (sleva pokryla vše).
  free,
  /// 0 < due ≤ 1 Kč — neúčtuje se, potvrdí se bez platby.
  waive,
  /// 1 < due < 15 Kč — platí se 15 Kč.
  round,
  /// due ≥ 15 Kč — platí se částka beze změny.
  normal,
}

class CardCharge {
  /// Serverová částka k zaplacení (Kč, může mít haléře).
  final double due;
  /// Kolik se strhne kartou (celé Kč; 0 = bez platby).
  final int charge;
  /// Dorovnání (+) / odpuštěná částka (−), 0 = žádné.
  final double rounding;
  final CardChargeKind kind;
  const CardCharge(this.due, this.charge, this.rounding, this.kind);

  bool get isRound => kind == CardChargeKind.round;
  bool get isWaive => kind == CardChargeKind.waive;
  /// Kartou se nic neplatí (zdarma nebo odpuštěno).
  bool get noCharge => charge <= 0;
}

double _r2(num v) => (v * 100).roundToDouble() / 100;

/// Zařazení částky [due] podle pravidla minimální platby kartou.
/// [forceMin] = server zbytek do 1 Kč odpustit nemůže (`below_minimum` s
/// `waiver_unverified`: SOS náhrada, úprava místa / doplňků / slevy) → platí
/// se 15 Kč s dorovnáním, jinak by se odpuštění (0 Kč) posílalo dokola.
CardCharge cardCharge(num due, {bool forceMin = false}) {
  final d = _r2(due);
  if (d <= 0) return const CardCharge(0, 0, 0, CardChargeKind.free);
  if (d <= cardWaiveMaxCzk && !forceMin) return CardCharge(d, 0, _r2(-d), CardChargeKind.waive);
  if (d < cardMinCzk) return CardCharge(d, cardMinCzk, _r2(cardMinCzk - d), CardChargeKind.round);
  return CardCharge(d, d.round(), 0, CardChargeKind.normal);
}

/// Přesná částka v Kč pro hlášky o minimu („7,50 Kč", „15 Kč") — běžný
/// `Money.czk` zaokrouhluje na celé koruny a u 0,60 Kč by ukázal „1 Kč".
/// Minimum karty je v Kč (Stripe účtuje CZK), proto vždy Kč.
String kcExact(num v) {
  final x = _r2(v.abs());
  final whole = x == x.roundToDouble();
  final s = whole ? x.toStringAsFixed(0) : x.toStringAsFixed(2).replaceAll('.', ',');
  return '${v < 0 ? '−' : ''}$s Kč';
}

final _rnd = Random.secure();
const _abc = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// Identita jednoho klepnutí „Zaplatit" (`attempt_id`, D4) — server z ní
/// skládá idempotenční klíč Stripe: ztracená odpověď + znovuodeslání téhož
/// pokusu nikdy nestrhne podruhé. Nový pokus = nové id.
String newAttemptId() =>
    'a${List.generate(23, (_) => _abc[_rnd.nextInt(_abc.length)]).join()}';
