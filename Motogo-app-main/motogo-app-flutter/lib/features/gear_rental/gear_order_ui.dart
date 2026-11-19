import 'package:flutter/material.dart';

import '../../core/currency.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/v2/calendar/trip_day_state.dart' show tripDate;
import 'gear_order_state.dart';

/// Textová pole formuláře (drží je obrazovka, hodnoty zrcadlí stav).
class GearOrderFields {
  final name = TextEditingController();
  final phone = TextEditingController();
  final street = TextEditingController();
  final zip = TextEditingController();
  final city = TextEditingController();
  final company = TextEditingController();
  final ico = TextEditingController();
  final dic = TextEditingController();
  final note = TextEditingController();
  final voucher = TextEditingController();

  void fillFrom(GearContact c) {
    void s(TextEditingController t, String v) {
      if (t.text.isEmpty && v.isNotEmpty) t.text = v;
    }

    s(name, c.name);
    s(phone, c.phone);
    s(street, c.street);
    s(zip, c.zip);
    s(city, c.city);
    s(company, c.company);
    s(ico, c.ico);
    s(dic, c.dic);
  }

  void dispose() {
    for (final c in [name, phone, street, zip, city, company, ico, dic, note, voucher]) {
      c.dispose();
    }
  }
}

/// Akce obrazovky předávané oběma vzhledům.
class GearOrderActions {
  final VoidCallback back;
  final VoidCallback retry;
  final void Function(String key, bool on) toggleItem;
  final void Function(String key) toggleSet;
  final VoidCallback submit;
  const GearOrderActions({
    required this.back,
    required this.retry,
    required this.toggleItem,
    required this.toggleSet,
    required this.submit,
  });
}

/// Částka v měně appky (web `G.money`).
String gearMoney(num czk) => Money.czk(czk);

/// „17. 10. – 19. 10. 2026“ / „17. 10. 2026“ (web `G.period`).
String gearPeriod(AppTranslations tr, DateTime a, DateTime b) {
  if (a.year == b.year && a.month == b.month && a.day == b.day) return tripDate(tr, a);
  return '${tr.trArgs('v2CalDateShort', {'d': a.day, 'm': a.month})} – ${tripDate(tr, b)}';
}

/// Název kusu v kompletu malým písmenem („helma M“); němčina beze změny.
String gearLc(String lang, String s) => lang == 'de' ? s : s.toLowerCase();

/// „pobočka · termín (3 dny)“ — první řádek souhrnu.
String gearSumMeta(AppTranslations tr, GearOrderState s) {
  final b = s.branch;
  if (b == null || s.start == null || s.end == null) return '';
  return '${b.name} · ${gearPeriod(tr, s.start!, s.end!)} (${s.nDays} ${tr.daysWord(s.nDays)})';
}
