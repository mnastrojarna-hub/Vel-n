import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import 'gear_contract.dart';

/// Volání backendu objednávky výbavy (RPC jako web `js/gear-rental*.js`).
/// HTTP / PostgREST chyba = `{error:'rpc_error'}` (web `G.rpc`), výpadek
/// sítě = výjimka. Testy podstrčí vlastní [rpc] přes [gearOrderApiProvider].
class GearOrderApi {
  const GearOrderApi();

  Future<Map<String, dynamic>> rpc(String fn, Map<String, dynamic> params) async {
    try {
      final res = await MotoGoSupabase.client.rpc(fn, params: params);
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } on PostgrestException catch (e) {
      return {'error': 'rpc_error', 'code': e.code, 'message': e.message};
    }
  }

  /// `{enabled:false}` / `{enabled:true, sizes:{helmet:{"M":2}}}`.
  Future<Map<String, dynamic>> availability(String branchId, String start, String end) =>
      rpc('get_gear_rental_availability', {'p_branch_id': branchId, 'p_start': start, 'p_end': end});

  Future<Map<String, dynamic>> quote(
    String branchId,
    String start,
    String end,
    List<Map<String, dynamic>> items,
    String? voucher,
  ) =>
      rpc('quote_gear_booking', {
        'p_branch_id': branchId,
        'p_start': start,
        'p_end': end,
        'p_items': items,
        'p_voucher_code': voucher,
      });

  Future<Map<String, dynamic>> create(Map<String, dynamic> params) =>
      rpc('create_web_gear_booking', params);
}

final gearOrderApiProvider = Provider<GearOrderApi>((ref) => const GearOrderApi());

/// Text k zobrazení: klíč překladu + dosazované hodnoty.
class GearMsg {
  final String key;
  final Map<String, Object?> args;
  const GearMsg(this.key, [this.args = const {}]);

  String text(AppTranslations tr) => tr.trArgs(key, args);

  @override
  bool operator ==(Object other) => other is GearMsg && other.key == key && '${other.args}' == '$args';

  @override
  int get hashCode => Object.hash(key, '$args');
}

double gearNum(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// Odečet dárkového poukazu z odpovědi (web `G.voucherAmt`).
double gearVoucherAmount(Map<String, dynamic> o) {
  final v = o['voucher'];
  final a = gearNum(o['voucher_amount']);
  if (a > 0) return a;
  final b = v is Map ? gearNum(v['amount']) : 0.0;
  if (b > 0) return b;
  return gearNum(o['discount_amount']);
}

/// „helma M, bunda L“ z `items:[{key,size}]` (web `G.itemsLabel`).
String gearItemsLabel(Object? list, Map<String, GearPrice> by) {
  if (list is! List) return '';
  return list.whereType<Map>().map((it) {
    final p = by['${it['key']}'];
    final z = '${it['size'] ?? ''}';
    return '${p?.label ?? '${it['key'] ?? ''}'}${z.isNotEmpty ? ' $z' : ''}';
  }).join(', ');
}

String _item(Map<String, dynamic> o, Map<String, GearPrice> by) {
  final k = '${o['key'] ?? ''}';
  return by[k]?.label ?? '';
}

/// Varování k ceně / skladu (web `G.errText`); null = bez chyby.
GearMsg? gearErrMsg(Map<String, dynamic> o, Map<String, GearPrice> by, int maxDays) {
  final e = o['error'];
  if (e == null || '$e'.isEmpty) return null;
  switch ('$e') {
    case 'out_of_stock':
      return GearMsg('groErrStock', {'items': gearItemsLabel(o['items'], by)});
    case 'below_minimum':
      return const GearMsg('groErrMin');
    case 'branch_closed':
      return const GearMsg('groErrClosed');
    case 'too_long':
      return GearMsg('groErrLong', {'n': o['max_days'] ?? maxDays});
    case 'bad_size':
      return GearMsg('groErrSize', {'item': _item(o, by)});
    case 'disabled':
      return const GearMsg('groErrDisabled');
    case 'bad_dates':
      return const GearMsg('groErrDates');
  }
  return const GearMsg('groErrGeneric');
}

/// Chyby `create_web_gear_booking` s vlastním textem (web submit `ERR`).
const Map<String, String> kGearCreateErr = {
  'bad_size': 'groErrSize',
  'branch_closed': 'groErrClosed',
  'too_long': 'groErrLong',
  'disabled': 'groErrDisabled',
  'bad_customer': 'groErrContact',
  'bad_branch': 'groErrBranch',
  'branch_unavailable': 'groErrBranch',
  'bad_dates': 'groErrDates',
  'no_items': 'groErrItems',
  'consents_required': 'groErrAgree',
  'too_many': 'groErrTooMany',
  'below_minimum': 'groErrMin',
  'bad_voucher': 'groVoucherBad',
};

/// Text chyby založení rezervace (známé kódy, jinak obecná chyba).
GearMsg gearCreateErrMsg(Map<String, dynamic> o, Map<String, GearPrice> by, int maxDays, {String email = ''}) {
  final e = '${o['error'] ?? ''}';
  if (e == 'email_mismatch') return GearMsg('groErrMismatch', {'email': o['email'] ?? email});
  if (e == 'out_of_stock') return gearErrMsg(o, by, maxDays)!;
  final k = kGearCreateErr[e];
  if (k == null) return const GearMsg('groErrGeneric');
  return GearMsg(k, {'n': o['max_days'] ?? maxDays, 'item': _item(o, by)});
}
