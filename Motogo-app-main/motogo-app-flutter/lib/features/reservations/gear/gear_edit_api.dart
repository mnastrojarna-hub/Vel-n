import '../../../core/i18n/i18n_provider.dart';
import '../../../core/supabase_client.dart';
import '../reservation_models.dart';
import 'gear_models.dart';

/// Úpravy výpůjčky výbavy VÝHRADNĚ přes RPC (gear řádek přímý update
/// odmítne strážce `trg_zz_gear_booking_guard` i RLS): velikosti zdarma
/// (`customer_update_gear_sizes`), odebrání kusu (`customer_remove_gear_item`,
/// náhled `p_dry_run`), storno (`cancel_booking_tracked`). Pravidla = web
/// `pages-upravit-rezervaci-gearbk-view.js` (`_gearTabs`).

const _paidish = {'paid', 'partial_refund', 'refund_pending'};

bool gearPaid(Reservation r) => _paidish.contains(r.paymentStatus);

/// `YYYY-MM-DD` kalendářního dne rezervace (RPC vrací datum, tabulka
/// půlnoc UTC — obojí nese správný den v polích year/month/day).
String gearIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool _startNotPast(Reservation r) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return !DateTime(r.startDate.year, r.startDate.month, r.startDate.day).isBefore(today);
}

/// Web „Velikosti“: reserved + zaplaceno + začátek dnes či později + nepřevzato + kusy s velikostí.
bool gearSizesEditable(Reservation r) =>
    r.isGearOnly &&
    r.status == 'reserved' &&
    gearPaid(r) &&
    r.pickedUpAt == null &&
    _startNotPast(r) &&
    r.gearLines.any((l) => l.sizes.isNotEmpty);

/// Web „Odebrat kus“: reserved + zaplaceno + aspoň 2 kusy.
bool gearRemoveAllowed(Reservation r) =>
    r.isGearOnly && r.status == 'reserved' && gearPaid(r) && r.pickedUpAt == null && gearItemSizes(r).length >= 2;

/// Web „Storno“: reserved + zaplaceno (probíhající výpůjčku stornovat nejde).
bool gearCancelAllowed(Reservation r) =>
    r.isGearOnly && r.status == 'reserved' && gearPaid(r) && r.pickedUpAt == null && !r.isHandedOver;

/// Změna termínu (na webu): živá zaplacená výpůjčka.
bool gearDatesEditable(Reservation r) =>
    r.isGearOnly && (r.status == 'reserved' || r.status == 'active') && gearPaid(r);

/// Výsledek gear RPC: [data] při úspěchu, jinak kód chyby serveru.
class GearRpcResult {
  final Map<String, dynamic>? data;
  final String? error;
  const GearRpcResult.ok(this.data) : error = null;
  const GearRpcResult.fail(this.error) : data = null;
  bool get ok => error == null;
}

Future<GearRpcResult> gearRpc(String fn, Map<String, dynamic> params) async {
  try {
    final r = await MotoGoSupabase.client.rpc(fn, params: params).timeout(const Duration(seconds: 20));
    if (r is! Map) return const GearRpcResult.fail('failed');
    final m = Map<String, dynamic>.from(r);
    if (m['error'] != null || m['success'] == false) return GearRpcResult.fail('${m['error'] ?? 'failed'}');
    return GearRpcResult.ok(m);
  } catch (_) {
    return const GearRpcResult.fail('network');
  }
}

/// Volné kusy pobočky v termínu `{helmet: {"M": 2}}`; null = sklad se
/// nekontroluje / chyba (pak se nabízí celý ceník, rozhodne server).
Future<Map<String, Map<String, int>>?> fetchGearAvailability(Reservation r) async {
  final branch = r.branchId;
  if (branch == null) return null;
  try {
    final res = await MotoGoSupabase.client.rpc('get_gear_rental_availability', params: {
      'p_branch_id': branch,
      'p_start': gearIsoDate(r.startDate),
      'p_end': gearIsoDate(r.endDate),
    });
    if (res is! Map || res['enabled'] != true || res['sizes'] is! Map) return null;
    final out = <String, Map<String, int>>{};
    (res['sizes'] as Map).forEach((k, v) {
      if (v is Map) {
        out['$k'] = {for (final e in v.entries) '${e.key}': (e.value is num) ? (e.value as num).toInt() : 0};
      }
    });
    return out;
  } catch (_) {
    return null;
  }
}

/// Náhled odebrání kusu ze serveru (`p_dry_run: true`).
class GearRemovePreview {
  final double perDay;
  final bool noSaving;
  final int percent;
  final double refund;
  const GearRemovePreview({required this.perDay, required this.noSaving, required this.percent, required this.refund});

  static GearRemovePreview? fromJson(Map<String, dynamic> d, Reservation r) {
    final newPd = (d['new_per_day'] as num?)?.toDouble();
    if (newPd == null) return null;
    final oldPd = (d['old_per_day'] as num?)?.toDouble() ?? r.gearPerDay ?? 0;
    return GearRemovePreview(
      perDay: newPd,
      noSaving: d['price_unchanged'] is bool ? d['price_unchanged'] as bool : !(newPd < oldPd),
      percent: (d['refund_percent'] as num?)?.toInt() ?? 0,
      refund: (d['refund_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Kód chyby gear RPC → text (web `gearbk-tabs.js` ERR + `_gearErrKey`).
String gearEditErrorText(AppTranslations tr, String? code) => tr.tr(switch (code) {
      'not_editable' => 'gearErrStarted',
      'bad_size' => 'gearErrSize',
      'out_of_stock' => 'gearErrStock',
      'last_item' => 'gearErrLastItem',
      'not_paid' => 'gearErrNotPaid',
      'wrong_status' => 'gearEditClosed',
      'no_items' => 'gearSizesPick',
      _ => 'gearErrGeneric',
    });
