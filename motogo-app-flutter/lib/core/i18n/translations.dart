/// All translations — merged from base files.
/// Key structure mirrors _t() lookups from the original app.
/// Covers: auth, booking, reservations, SOS, shop, profile, common UI.
/// Languages: cs, en, de, es, fr, nl, pl
///
/// Split into partial files by language group:
///   translations_cs_pl.dart   — cs, pl
///   translations_en_de_nl.dart — en, de, nl
///   translations_es_fr.dart   — es, fr
import 'translations_cs_pl.dart';
import 'translations_en_de_nl.dart';
import 'translations_es_fr.dart';
import 'translations_ext_1_cs_pl.dart';
import 'translations_ext_1_en_de_nl.dart';
import 'translations_ext_1_es_fr.dart';

/// Deep-merges translation maps so all language keys are combined.
final translations = _mergeAll([
  translationsCsPl,
  translationsEnDeNl,
  translationsEsFr,
  translationsExt1CsPl,
  translationsExt1EnDeNl,
  translationsExt1EsFr,
]);

Map<String, Map<String, String>> _mergeAll(
  List<Map<String, Map<String, String>>> parts,
) {
  final result = <String, Map<String, String>>{};
  for (final part in parts) {
    for (final entry in part.entries) {
      result.putIfAbsent(entry.key, () => {});
      result[entry.key]!.addAll(entry.value);
    }
  }
  return result;
}
