import 'dart:math' as math;

import 'gear_contract.dart';
import 'gear_offer_provider.dart' show kGearSelfServiceType;
import 'gear_order_api.dart' show gearNum;
import 'gear_quote.dart' show gearCountDays;

/// Co ukázat na děkovací stránce (web `show()`).
enum GearDoneStage { wait, paid, pending, cancelled, completed, pay, notFound }

const _paidStates = {'paid', 'partial_refund', 'refund_pending'};

GearDoneStage gearDoneStage(GearDoneInfo? i, {required bool pending}) {
  if (i == null) return pending ? GearDoneStage.pending : GearDoneStage.notFound;
  if (i.status == 'cancelled') return GearDoneStage.cancelled;
  if (i.status == 'completed') return GearDoneStage.completed;
  if (i.paid) return GearDoneStage.paid;
  if (pending) return GearDoneStage.pending;
  if (i.canPay) return GearDoneStage.pay;
  return GearDoneStage.notFound;
}

/// Výpůjčka výbavy z `get_web_gear_booking` (tvar `_gear_booking_json`)
/// převedená pro potvrzení — stejné výpočty jako web `gear-rental-done.js`.
class GearDoneInfo {
  final Map<String, dynamic> o;
  final Map<String, GearPrice> by;
  GearDoneInfo(this.o, List<GearPrice> prices) : by = {for (final p in prices) p.key: p};

  String get id => '${o['id'] ?? ''}';
  String get status => '${o['status'] ?? ''}';
  bool get paid => _paidStates.contains(o['payment_status']);
  bool get canPay => o['can_pay'] == true;
  String get number => '${o['booking_number'] ?? ''}';
  DateTime? get createdAt => DateTime.tryParse('${o['created_at'] ?? ''}');

  Map get _branch => o['branch'] is Map ? o['branch'] as Map : const {};
  bool get self => _branch['type'] == kGearSelfServiceType;

  /// „Velké Němčice, Ulice 1, Město“ (bez „MotoGo24 “).
  String get branchLine => [
        '${_branch['name'] ?? ''}'.replaceFirst(RegExp(r'^MotoGo24\s*', caseSensitive: false), ''),
        '${_branch['address'] ?? ''}',
        '${_branch['city'] ?? ''}',
      ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');

  DateTime? _date(Object? v) {
    final s = '${v ?? ''}';
    return s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  }

  DateTime? get start => _date(o['start_date']);
  DateTime? get end => _date(o['end_date']) ?? start;

  int get days {
    final n = gearNum(o['days']).round();
    if (n > 0) return n;
    return start != null && end != null ? gearCountDays(start!, end!) : 0;
  }

  String? get pickupTime {
    final p = '${o['pickup_time'] ?? ''}';
    return p.isEmpty ? null : (p.length >= 5 ? p.substring(0, 5) : p);
  }

  double get voucher => gearNum(o['voucher_amount']);

  /// Plná cena: subtotal, jinak cena/den × dny, jinak total + poukaz.
  double get full {
    final sub = gearNum(o['subtotal']);
    if (sub > 0) return sub;
    final per = gearNum(o['per_day']);
    return per > 0 && days > 0 ? per * days : gearNum(o['total']) + voucher;
  }

  double get toPay {
    final t = o['total'];
    return math.max(0, t != null && '$t'.isNotEmpty ? gearNum(t) : full - voucher);
  }

  bool get showTotal => full > 0 || voucher > 0;

  bool get docsNeeded {
    final d = o['docs'];
    return d is Map && d['required'] == true && d['ok'] != true;
  }

  /// Řádky „název“ + „velikosti“ (pořadí kusů dle `includes`).
  List<(String, String)> lines(String Function(String) lc) {
    final ls = o['lines'];
    if (ls is! List) return const [];
    return [
      for (final l in ls.whereType<Map>())
        (
          by['${l['key']}']?.label ?? '${l['label'] ?? l['key'] ?? ''}',
          _sizes(l, lc),
        ),
    ];
  }

  String _sizes(Map l, String Function(String) lc) {
    final sizes = l['sizes'] is Map ? l['sizes'] as Map : const {};
    final inc = l['includes'] is List && (l['includes'] as List).isNotEmpty
        ? (l['includes'] as List).map((e) => '$e').toList()
        : sizes.keys.map((e) => '$e').toList();
    final set = l['kind'] == 'set';
    return inc
        .where((k) => '${sizes[k] ?? ''}'.isNotEmpty)
        .map((k) => set && by[k] != null ? '${lc(by[k]!.label)} ${sizes[k]}' : '${sizes[k]}')
        .join(', ');
  }
}
