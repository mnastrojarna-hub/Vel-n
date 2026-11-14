// Skener — volba dokladu (majitel 2026-11-08): volby říkají „doklad + řidičák“,
// pod každou je přesný seznam fotek podle skutečných kroků (i v režimu
// „doplnit chybějící“), nad volbami věta, co je k vyzvednutí potřeba.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_scan_choice.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/features/documents/v2/scan_choice_text_v2.dart';
import 'package:motogo_app/features/documents/v2/scan_choice_v2.dart';

import '../support/v2_harness.dart';

void _n() {}

Future<String> _sub(WidgetTester t, List<String> keys, {String lang = 'cs'}) async {
  late String out;
  await pumpV2(t, Builder(builder: (c) {
    out = scanChoiceSub(c, keys);
    return const SizedBox();
  }), lang: lang, scaffold: false);
  return out;
}

void main() {
  test('all 8 languages have the same keys, no empty values', () {
    final cs = translationsExt60V2ScanChoice['cs']!.keys.toSet();
    for (final l in ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
      final m = translationsExt60V2ScanChoice[l]!;
      expect(m.keys.toSet(), cs, reason: l);
      expect(m.values.where((v) => v.trim().isEmpty), isEmpty, reason: l);
    }
  });

  testWidgets('photo list follows the real steps (full + missing modes)', (t) async {
    expect(await _sub(t, ['id_front', 'id_back', 'dl_front', 'dl_back']), '4 fotky: občanka z obou stran, řidičák z obou stran');
    expect(await _sub(t, ['passport_front', 'passport_back', 'dl_front', 'dl_back']),
        '4 fotky: pas – stránka s fotkou a stránka s adresou, řidičák z obou stran');
    expect(await _sub(t, ['dl_front', 'dl_back']), '2 fotky: řidičák z obou stran');
    expect(await _sub(t, ['id_back', 'dl_front']), '2 fotky: občanka – zadní strana, řidičák – přední strana');
    expect(await _sub(t, ['passport_front']), '1 fotka: pas – stránka s fotkou');
    expect(await _sub(t, ['id_front', 'id_back', 'dl_front', 'dl_back'], lang: 'en'), '4 photos: ID card, both sides, driving licence, both sides');
  });

  testWidgets('choice screen: note under the title, rows show label + photo list, tap runs the action', (t) async {
    final hits = <String>[];
    await pumpV2(
        t,
        ScanChoiceV2(onBack: _n, note: 'K vyzvednutí motorky potřebujeme doklad totožnosti (občanku nebo pas) a řidičský průkaz.', choices: [
          (icon: MgIcons.idCard, label: 'Občanský průkaz + řidičák', steps: 4, sub: '4 fotky: občanka z obou stran, řidičák z obou stran', onTap: () => hits.add('op')),
          (icon: MgIcons.doc, label: 'Cestovní pas + řidičák', steps: 4, sub: '4 fotky: pas – stránka s fotkou a stránka s adresou, řidičák z obou stran', onTap: () => hits.add('passport')),
        ]),
        scaffold: false, size: const Size(320, 690));
    await t.pump();
    expect(find.textContaining('potřebujeme doklad totožnosti'), findsOneWidget);
    expect(find.text('4 fotky: občanka z obou stran, řidičák z obou stran'), findsOneWidget);
    expect(find.textContaining('× skenovat'), findsNothing);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Cestovní pas + řidičák'));
    expect(hits, ['passport']);
  });
}
