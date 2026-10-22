// Platby D1–D6 (rozhodnutí majitele 2026-10-16): minimum karty 15 Kč
// (dorovnání / do 1 Kč se neúčtuje), obnovení zrušené rezervace, dokončení
// zaplacené výměny / úpravy (fronta), přesné hlášky BEZ kontaktů.
// Klíče `pd*`, 8 jazyků; jeden soubor = jeden jazyk (limit velikosti).
import 'translations_ext_43_payments_cs.dart';
import 'translations_ext_43_payments_de.dart';
import 'translations_ext_43_payments_en.dart';
import 'translations_ext_43_payments_es.dart';
import 'translations_ext_43_payments_fr.dart';
import 'translations_ext_43_payments_nl.dart';
import 'translations_ext_43_payments_pl.dart';
import 'translations_ext_43_payments_uk_a.dart';
import 'translations_ext_43_payments_uk_b.dart';

const Map<String, Map<String, String>> translationsExt43Payments = {
  'cs': ext43PaymentsCs,
  'en': ext43PaymentsEn,
  'de': ext43PaymentsDe,
  'es': ext43PaymentsEs,
  'fr': ext43PaymentsFr,
  'nl': ext43PaymentsNl,
  'pl': ext43PaymentsPl,
  'uk': {...ext43PaymentsUkA, ...ext43PaymentsUkB},
};
