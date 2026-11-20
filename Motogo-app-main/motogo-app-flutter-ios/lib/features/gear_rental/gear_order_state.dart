import 'dart:math' as math;

import 'gear_contract.dart';
import 'gear_offer_provider.dart';
import 'gear_order_api.dart';
import 'gear_quote.dart';

export 'gear_order_controller.dart';

/// Podklady formuláře (načtené jednou při otevření).
class GearOrderData {
  final GearRentalSettings cfg;
  final List<GearPrice> prices;
  final List<GearBranch> branches;
  final List<GearClosure> closures;
  final DateTime today;
  GearOrderData({
    required this.cfg,
    required this.prices,
    required this.branches,
    required this.closures,
    required this.today,
  }) : by = {for (final p in prices) p.key: p};

  final Map<String, GearPrice> by;

  /// Formulář jen se zapnutou službou a neprázdným ceníkem (web `$enabled`).
  bool get available => cfg.enabled && prices.isNotEmpty;
}

/// Kontakt (web sekce 4). E-mail = e-mail účtu (jen ke čtení).
class GearContact {
  String name = '', email = '', phone = '', street = '', zip = '', city = '';
  String company = '', ico = '', dic = '';

  GearContact copy() => GearContact()
    ..name = name
    ..email = email
    ..phone = phone
    ..street = street
    ..zip = zip
    ..city = city
    ..company = company
    ..ico = ico
    ..dic = dic;
}

/// Stav objednávky (zrcadlo `MGGR.S` webu). Měnitelná kopie: kontrolér
/// vždy upraví [copy] a nastaví ji jako nový stav.
class GearOrderState {
  GearOrderData? data;
  String? branchId;
  DateTime? start, end;
  bool open = false;
  GearMsg? calNote;
  DateTime? month;
  Map<String, String> sel = {};
  List<GearMsg> drops = const [];
  Map<String, dynamic>? avail;
  String availKey = '';
  String quoteKey = '';
  bool quoteWait = false;
  Map<String, dynamic>? quoteRes;
  bool voucherOn = false;
  String vcode = '';
  String vstate = '';
  String pickupTime = '09:00';
  GearContact contact = GearContact();
  bool companyOn = false;
  String note = '';
  bool vop = false, gdpr = false;
  bool busy = false;
  GearMsg? error;
  String? draftId;

  GearOrderState copy() => GearOrderState()
    ..data = data
    ..branchId = branchId
    ..start = start
    ..end = end
    ..open = open
    ..calNote = calNote
    ..month = month
    ..sel = Map.of(sel)
    ..drops = drops
    ..avail = avail
    ..availKey = availKey
    ..quoteKey = quoteKey
    ..quoteWait = quoteWait
    ..quoteRes = quoteRes
    ..voucherOn = voucherOn
    ..vcode = vcode
    ..vstate = vstate
    ..pickupTime = pickupTime
    ..contact = contact.copy()
    ..companyOn = companyOn
    ..note = note
    ..vop = vop
    ..gdpr = gdpr
    ..busy = busy
    ..error = error
    ..draftId = draftId;

  List<GearPrice> get prices => data?.prices ?? const [];

  GearBranch? get branch {
    for (final b in data?.branches ?? const <GearBranch>[]) {
      if (b.id == branchId) return b;
    }
    return null;
  }

  bool get isSelf => branch?.self ?? false;
  int get nDays => start != null && end != null ? gearCountDays(start!, end!) : 0;
  List<String> get keys => gearSelectedKeys(prices, sel);

  bool get complete => gearComplete(prices, sel, hasBranch: branch != null, start: start, end: end);

  /// `[{key,size}]` pro RPC (prázdná velikost = null).
  List<Map<String, dynamic>> get itemsArg => [
        for (final k in keys) {'key': k, 'size': (sel[k] ?? '').isEmpty ? null : sel[k]},
      ];

  GearDay dayState(DateTime d) => data == null
      ? GearDay.busy
      : gearDayState(d,
          today: data!.today, maxAhead: data!.cfg.maxAheadDays, closures: data!.closures, branchId: branchId);

  bool rangeOk(DateTime a, DateTime b) =>
      data != null &&
      gearRangeOk(a, b,
          today: data!.today, maxAhead: data!.cfg.maxAheadDays, closures: data!.closures, branchId: branchId);

  /// Nápověda nad kalendářem (web `renderCal`).
  GearMsg get hint => calNote ??
      GearMsg(start == null ? 'groHintStart' : (open ? 'groHintEnd' : 'groHintDone'));

  GearSummary get summary => GearSummary.of(this);
}

/// Souhrn ceny (web `renderSum`): klientské nacenění, serverová cena a poukaz.
class GearSummary {
  final bool empty;
  final GearQuote quote;
  final int days;
  final double full;
  final double voucher;
  final double pay;
  final String voucherCode;
  final GearMsg? warn;

  const GearSummary({
    required this.empty,
    required this.quote,
    required this.days,
    required this.full,
    required this.voucher,
    required this.pay,
    this.voucherCode = '',
    this.warn,
  });

  factory GearSummary.of(GearOrderState s) {
    final q = gearQuote(s.prices, s.sel);
    final n = s.nDays;
    if (q.lines.isEmpty || n == 0 || s.branch == null) {
      return GearSummary(empty: true, quote: q, days: n, full: 0, voucher: 0, pay: 0);
    }
    final r = s.quoteWait ? null : s.quoteRes;
    final ok = r != null && r['error'] == null;
    var full = q.perDay * n;
    if (ok && gearNum(r['per_day']) > 0) full = gearNum(r['per_day']) * n;
    final va = ok ? gearVoucherAmount(r) : 0.0;
    final pay = va > 0 ? (r!['amount'] != null ? gearNum(r['amount']) : math.max(0.0, full - va)) : full;
    final err = r?['error'];
    final warn = r != null && err != null && err != 'bad_voucher'
        ? gearErrMsg(r, s.data!.by, s.data!.cfg.maxDays)
        : null;
    final v = r?['voucher'];
    return GearSummary(
      empty: false,
      quote: q,
      days: n,
      full: full,
      voucher: va,
      pay: pay,
      voucherCode: v is Map && '${v['code'] ?? ''}'.isNotEmpty ? '${v['code']}' : s.vcode,
      warn: warn,
    );
  }

  /// Velikosti řádku: u kompletu „helma M, bunda L“, u kusu „M“.
  static String lineSizes(GearPrice l, GearOrderState s, String Function(String) lc) {
    final ks = l.isSet ? l.includes : [l.key];
    return ks
        .where((k) => (s.sel[k] ?? '').isNotEmpty)
        .map((k) => l.isSet ? '${lc(s.data?.by[k]?.label ?? '')} ${s.sel[k]}'.trim() : s.sel[k]!)
        .join(', ');
  }
}
