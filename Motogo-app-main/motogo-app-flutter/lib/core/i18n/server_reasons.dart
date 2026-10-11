import 'i18n_provider.dart';

/// Důvody zadržení přístupových kódů / chybějících dokladů chodí z DB česky
/// (`check_booking_docs_status`, `branch_door_codes.withheld_reason` — Velín
/// je česky). Appka známé texty mapuje na i18n klíče. Česká appka dostane
/// text 1:1; neznámý text v cizím jazyce → null (UI ukáže vlastní obecnou
/// hlášku, nikdy syrovou češtinu).
String? localizeServerReason(AppTranslations tr, String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  if (tr.lang == 'cs') return s;
  const known = <String, String>{
    'Chybí doklady (OP/pas/ŘP)': 'reasonMissingDocs',
    'Chybí doklad totožnosti (OP/pas)': 'reasonMissingId',
    'Chybí ŘP': 'reasonMissingDl',
    'Vraťte nejdřív původní motorku': 'reasonSwapReturnFirst',
    'Vlastní výbava': 'reasonOwnGear',
  };
  final key = known[s];
  if (key != null) return tr.tr(key);
  final expired = RegExp(r'^ŘP propadlý\s+(.+)$').firstMatch(s);
  if (expired != null) return tr.trArgs('reasonDlExpired', {'date': expired.group(1)});
  return null;
}
