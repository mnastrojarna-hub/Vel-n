import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/i18n/i18n_provider.dart';

/// Záznamy `sos_timeline.action` píše appka, DB i Velín ČESKY (operátor je
/// vždy česky). Zákazníkovi v cizojazyčné appce známé texty přeložíme;
/// neznámý text (volná poznámka operátora) zůstane, jak je.
String localizeSosAction(AppTranslations tr, String action) {
  final a = action.trim();
  if (tr.lang == 'cs' && !_codes.containsKey(a)) return a;
  final code = _codes[a] ?? _exact[a];
  if (code != null) return tr.tr(code);
  for (final p in _patterns) {
    final m = p.$1.firstMatch(a);
    if (m != null) {
      var s = tr.tr(p.$2);
      for (var i = 1; i <= m.groupCount; i++) {
        final g = m.group(i) ?? '';
        // Typ incidentu z DB triggeru je kód (accident_minor…) → přeložit.
        s = s.replaceAll('{$i}', _typeKeys[g] != null ? tr.tr(_typeKeys[g]!) : g);
      }
      return s.replaceAll(RegExp(r'\s*\(\)'), '').trim();
    }
  }
  return a;
}

/// Technické kódy z DB (`create_sos_incident`, `share_sos_location`, Velín).
const _codes = <String, String>{
  'reported': 'reported',
  'gps_shared': 'locationShared',
  'admin_note': 'sosTlAdminNote',
};

const _exact = <String, String>{
  'Zákazník ukončuje jízdu — žádá odtah (zaviněná)': 'sosTlEndRideFault',
  'Zákazník ukončuje jízdu — žádá odtah (nezaviněná / porucha)': 'sosTlEndRideNoFault',
  'Zákazník pokračuje v jízdě (jedu dál)': 'sosTlContinue',
  'Zákazník nahrál fakturu za servis': 'sosTlServiceInvoice',
  'Zákazník telefonicky kontaktován': 'sosTlCustomerCalled',
  'Odtahová služba objednána — motorka bude odtažena do servisu': 'sosTlTowOrdered',
  'Zákazník navigován na nejbližší servis': 'sosTlNavigatedToService',
  'Pojišťovna kontaktována, hlášena škodná událost': 'sosTlInsurerContacted',
  'Zavinění: zákazník (platí náklady)': 'sosTlFaultCustomer',
  'Zavinění: cizí (bez nákladů pro zákazníka)': 'sosTlFaultOther',
};

final _patterns = <(RegExp, String)>[
  (RegExp(r'^Zákazník objednal náhradní motorku: (.+) \(zdarma\)$'), 'sosTlReplacementOrdered'),
  (RegExp(r'^Operátor přiřadil náhradní motorku: (.+?) — .*$'), 'sosTlReplacementAssigned'),
  (RegExp(r'^Incident založen operátorem \(Velín\): (.+)$'), 'sosTlCreatedByOperator'),
  (RegExp(r'^Incident nahlasen zakaznikem \((.+)\)$'), 'sosTlReportedByCustomer'),
  (RegExp(r'^Policie ČR kontaktována(?:, číslo spisu: (.+))?$'), 'sosTlPoliceContacted'),
];

const _typeKeys = <String, String>{
  'theft': 'theft',
  'accident_minor': 'accidentMinorLabel',
  'accident_major': 'accidentMajorLabel',
  'breakdown_minor': 'breakdownMinorLabel',
  'breakdown_major': 'breakdownMajorLabel',
  'defect_question': 'defectQuestionLabel',
  'location_share': 'shareLocation',
  'other': 'other',
};

/// Chyba SOS akce pro zákazníka — nikdy syrová výjimka (dřív i česká
/// „Nepřihlášen — přihlaste se znovu“ ve všech jazycích).
String sosErrorMessage(AppTranslations tr, Object e) {
  debugPrint('[SOS] action failed: $e');
  return e.toString().contains('Nepřihlášen') ? tr.tr('notLoggedIn') : tr.tr('errUnknown');
}
