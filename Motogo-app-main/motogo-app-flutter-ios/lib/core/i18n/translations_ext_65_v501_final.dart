/// 5.0.1 (nový vzhled), závěrečná oprava: kalendář Motorek v zimě (proč jsou
/// dny přeškrtnuté + legenda „Zavřeno") a počet motorek s českým tvarem
/// („1 motorka", „2–4 motorky"). Sdílené klíče obou stromů appky.
/// Tyká se ve všech jazycích.
const Map<String, Map<String, String>> translationsExt65V501Final = {
  'cs': {
    'calLegClosed': 'Zavřeno',
    'motoCalClosedFreeFrom': 'Pobočky mají zavřeno · volné dny od {date}',
    'motoShownOne': 'Zobrazeno: {n} motorka',
    'motoShownFew': 'Zobrazeno: {n} motorky',
  },
  'en': {
    'calLegClosed': 'Closed',
    'motoCalClosedFreeFrom': 'Our branches are closed · free days from {date}',
    'motoShownOne': 'Shown: {n} motorcycle',
    'motoShownFew': 'Shown: {n} motorcycles',
  },
  'de': {
    'calLegClosed': 'Geschlossen',
    'motoCalClosedFreeFrom': 'Die Filialen haben zu · freie Tage ab {date}',
    'motoShownOne': 'Angezeigt: {n} Motorrad',
    'motoShownFew': 'Angezeigt: {n} Motorräder',
  },
  'es': {
    'calLegClosed': 'Cerrado',
    'motoCalClosedFreeFrom': 'Las sucursales están cerradas · días libres desde el {date}',
    'motoShownOne': 'Mostrada: {n} moto',
    'motoShownFew': 'Mostradas: {n} motos',
  },
  'fr': {
    'calLegClosed': 'Fermé',
    'motoCalClosedFreeFrom': 'Les agences sont fermées · jours libres dès le {date}',
    'motoShownOne': 'Affichée : {n} moto',
    'motoShownFew': 'Affichées : {n} motos',
  },
  'nl': {
    'calLegClosed': 'Gesloten',
    'motoCalClosedFreeFrom': 'De vestigingen zijn gesloten · vrije dagen vanaf {date}',
    'motoShownOne': 'Getoond: {n} motor',
    'motoShownFew': 'Getoond: {n} motoren',
  },
  'pl': {
    'calLegClosed': 'Zamknięte',
    'motoCalClosedFreeFrom': 'Oddziały są zamknięte · wolne dni od {date}',
    'motoShownOne': 'Wyświetlono: {n} motocykl',
    'motoShownFew': 'Wyświetlono: {n} motocykle',
  },
  'uk': {
    'calLegClosed': 'Зачинено',
    'motoCalClosedFreeFrom': 'Філії зачинені · вільні дні з {date}',
    'motoShownOne': 'Показано: {n} мотоцикл',
    'motoShownFew': 'Показано: {n} мотоцикли',
  },
};

/// "Zobrazeno: n motorek" with the language's plural form (5.0.1 FV-08,
/// new look only): 1 → [motoShownOne], few (cs 2–4; pl / uk 2–4, 22–24 …)
/// → [motoShownFew], else the old key [manyKey] unchanged.
String motoShownCount(String lang, String Function(String) tr, int n, String manyKey) {
  final few = switch (lang) {
    'cs' => n >= 2 && n <= 4,
    'pl' || 'uk' => n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14),
    _ => false,
  };
  final key = n == 1 ? 'motoShownOne' : (few ? 'motoShownFew' : manyKey);
  return tr(key).replaceAll('{n}', '$n');
}
