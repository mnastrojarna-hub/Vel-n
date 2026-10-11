/// Jazyky, které appka zapisuje do DB (`bookings` / `profiles` /
/// `shop_orders.language`) a posílá edge funkcím (dokumenty, AI, e-maily).
/// Musí odpovídat CHECK omezením `*_language_check` (migrace 20261011
/// přidala 'uk') a seznamu `supportedLocales` v i18n_provider.dart.
const appLanguageCodes = <String>{'cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'};

/// Normalizuje kód jazyka ('uk-UA' → 'uk', 'EN' → 'en'). Prázdný = 'cs'
/// (výchozí jazyk appky); nepodporovaný = 'en' — cizinec má raději dostat
/// angličtinu než češtinu.
String normalizeAppLang(String? raw) {
  final code = (raw ?? '').trim().toLowerCase().split(RegExp(r'[-_]')).first;
  if (code.isEmpty) return 'cs';
  return appLanguageCodes.contains(code) ? code : 'en';
}

/// DB odmítla hodnotu jazyka (CHECK `*_language_check`, chyba 23514). Živá DB
/// před migrací 20261011 nezná 'uk' — volající zápis zopakuje s 'en', aby
/// kvůli jazyku nikdy nespadla rezervace ani uložení profilu.
bool isLanguageCheckViolation(Object e) => e.toString().contains('language_check');
