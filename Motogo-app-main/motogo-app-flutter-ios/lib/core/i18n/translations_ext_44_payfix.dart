// Platby D1–D6 — oprava po kontrole (2026-10-16): výměna motorky, předchozí
// zaplacená úprava, PSČ / „neopakovat" u karty, rezervace začínající dnes,
// konečné stavy dokončení zaplacené změny, chyby serveru BEZ kontaktu (D5).
// 8 jazyků, po dvou v souboru (limit velikosti).
import 'translations_ext_44_payfix_a.dart';
import 'translations_ext_44_payfix_b.dart';
import 'translations_ext_44_payfix_c.dart';
import 'translations_ext_44_payfix_d.dart';

const Map<String, Map<String, String>> translationsExt44Payfix = {
  'cs': ext44PayfixCs,
  'en': ext44PayfixEn,
  'de': ext44PayfixDe,
  'es': ext44PayfixEs,
  'fr': ext44PayfixFr,
  'nl': ext44PayfixNl,
  'pl': ext44PayfixPl,
  'uk': ext44PayfixUk,
};
