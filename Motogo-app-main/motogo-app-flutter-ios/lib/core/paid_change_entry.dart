/// Položka trvalé fronty zaplacených změn rezervace (D6) — viz
/// [PaidChangeQueue]. Serializuje se do SharedPreferences (krátké klíče).
class PaidChangeEntry {
  /// Klíč = id PaymentIntentu doplatku (`pi_…`).
  final String key;
  final String bookingId;
  /// 'swap' (výměna motorky) | 'edit' (úprava rezervace).
  final String kind;
  /// Zaplacená částka (Kč) — do textů („Doplatek 15 Kč je zaplacený").
  final double charge;
  /// true = appka ví, že platba prošla (Stripe Succeeded / Processing).
  /// false = zapsáno při odeslání platby (pojistka pro pád appky) — UI ji
  /// neukazuje, server ji případně uklidí jako „nezaplaceno".
  final bool paid;
  /// Doplňky k nahrazení po zápisu změny (nejsou ve Stripe metadatech):
  /// {rows, del (id původních řádků), orig (id původních doplňků)}.
  final Map<String, dynamic>? extras;
  /// Sloupce pro starou klientskou cestu (`client_apply`).
  final Map<String, dynamic>? columns;
  /// Parametry výměny pro starou klientskou cestu (`client_apply`).
  final Map<String, dynamic>? swap;
  final int createdAt;
  final int attempts;
  final int nextAt;
  /// 'pending' (čeká na server) | 'extras' (zapsáno, zbývají doplňky) | 'failed'.
  final String state;
  /// U 'failed': {reason, refund, amount}.
  final Map<String, dynamic>? failure;

  const PaidChangeEntry({
    required this.key,
    required this.bookingId,
    required this.kind,
    required this.charge,
    this.paid = true,
    this.extras,
    this.columns,
    this.swap,
    this.createdAt = 0,
    this.attempts = 0,
    this.nextAt = 0,
    this.state = 'pending',
    this.failure,
  });

  bool get isSwap => kind == 'swap';
  bool get isFailed => state == 'failed';

  PaidChangeEntry copyWith({
    bool? paid,
    int? attempts,
    int? nextAt,
    String? state,
    Map<String, dynamic>? failure,
    int? createdAt,
  }) =>
      PaidChangeEntry(
        key: key,
        bookingId: bookingId,
        kind: kind,
        charge: charge,
        paid: paid ?? this.paid,
        extras: extras,
        columns: columns,
        swap: swap,
        createdAt: createdAt ?? this.createdAt,
        attempts: attempts ?? this.attempts,
        nextAt: nextAt ?? this.nextAt,
        state: state ?? this.state,
        failure: failure ?? this.failure,
      );

  Map<String, dynamic> toJson() => {
        'k': key,
        'b': bookingId,
        't': kind,
        'c': charge,
        'p': paid,
        if (extras != null) 'x': extras,
        if (columns != null) 'cols': columns,
        if (swap != null) 'sw': swap,
        'at': createdAt,
        'n': attempts,
        'next': nextAt,
        's': state,
        if (failure != null) 'f': failure,
      };

  static PaidChangeEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final k = raw['k'], b = raw['b'];
    if (k is! String || b is! String || k.isEmpty) return null;
    Map<String, dynamic>? m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;
    return PaidChangeEntry(
      key: k,
      bookingId: b,
      kind: raw['t'] == 'swap' ? 'swap' : 'edit',
      charge: (raw['c'] as num?)?.toDouble() ?? 0,
      paid: raw['p'] != false,
      extras: m(raw['x']),
      columns: m(raw['cols']),
      swap: m(raw['sw']),
      createdAt: (raw['at'] as num?)?.toInt() ?? 0,
      attempts: (raw['n'] as num?)?.toInt() ?? 0,
      nextAt: (raw['next'] as num?)?.toInt() ?? 0,
      state: '${raw['s'] ?? 'pending'}',
      failure: m(raw['f']),
    );
  }
}

/// Výsledek jednoho pokusu o dokončení.
enum PaidChangeStatus {
  /// Změna je zapsaná (i doplňky).
  done,
  /// Dokončuje se (banka zpracovává / server / síť) — zkusí se znovu samo.
  completing,
  /// Trvale nejde zapsat — doplatek se vrací (viz [PaidChangeResult.refund]).
  failed,
  /// Platba neproběhla — nic nestrženo, nic se nedokončuje.
  notPaid,
}

class PaidChangeResult {
  final PaidChangeStatus status;
  /// Telefon je offline (text „dokončíme po připojení").
  final bool offline;
  final String? reason;
  final String refund;
  final double? amount;
  final String? newBookingId;
  const PaidChangeResult(this.status,
      {this.offline = false, this.reason, this.refund = 'auto', this.amount, this.newBookingId});
}

/// Událost fronty (PaymentResultScreen / banner v detailu rezervace).
class PaidChangeEvent {
  final PaidChangeEntry entry;
  final PaidChangeResult result;
  const PaidChangeEvent(this.entry, this.result);
}
