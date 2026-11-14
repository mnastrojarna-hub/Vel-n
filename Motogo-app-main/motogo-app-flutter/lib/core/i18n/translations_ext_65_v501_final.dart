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

/// The plural form of [n] in [lang] (5.0.1, new look only): 1 → [one]
/// (uk also 21, 31 … but not 11), few (cs 2–4; pl / uk 2–4, 22–24 … but
/// not 12–14) → [few], else [many] (the old key, unchanged).
String motoCountKey(String lang, int n, String one, String few, String many) {
  final isOne = lang == 'uk' ? n % 10 == 1 && n % 100 != 11 : n == 1;
  final isFew = switch (lang) {
    'cs' => n >= 2 && n <= 4,
    'pl' || 'uk' => n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14),
    _ => false,
  };
  return isOne ? one : (isFew ? few : many);
}

/// "Zobrazeno: n motorek" with the language's plural form (FV-08).
String motoShownCount(String lang, String Function(String) tr, int n, String manyKey) =>
    tr(motoCountKey(lang, n, 'motoShownOne', 'motoShownFew', manyKey)).replaceAll('{n}', '$n');

/// "n volných motorek" (dates set) with the same plural form (FR-04).
String motoFreeCount(String lang, String Function(String) tr, int n) =>
    tr(motoCountKey(lang, n, 'motoFreeOne', 'motoFreeFew', 'searchAvailableMotorcycles')).replaceAll('{n}', '$n');
