// Home v2 strings (PLAN §4.2): every key in all 8 languages, non-empty,
// same placeholders as cs, `v2` prefix, no emoji, informal Czech; every
// key the Home v2 code uses exists. Works before the integration step
// registers the ext_51 files in translations.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_c.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_d.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _ph = RegExp(r'\{[a-zA-Z]+\}');
final _emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}]', unicode: true);

void main() {
  final all = <String, Map<String, String>>{};
  for (final part in [translationsExt51V2HomeA, translationsExt51V2HomeB, translationsExt51V2HomeC, translationsExt51V2HomeD]) {
    part.forEach((l, m) => all.putIfAbsent(l, () => {}).addAll(m));
  }

  test('all 8 languages with the same key set, v2 prefix, no collisions', () {
    final keys = all['cs']!.keys.toSet();
    expect(keys.length, greaterThan(100));
    for (final l in _langs) {
      expect(all[l]?.keys.toSet(), keys, reason: l);
    }
    for (final k in keys) {
      expect(k.startsWith('v2Home'), isTrue, reason: k);
    }
  });

  test('non-empty, same placeholders, no emoji', () {
    for (final k in all['cs']!.keys) {
      final ph = _ph.allMatches(all['cs']![k]!).map((m) => m.group(0)).toSet();
      for (final l in _langs) {
        final v = all[l]![k]!;
        expect(v.trim(), isNotEmpty, reason: '$l $k');
        expect(_ph.allMatches(v).map((m) => m.group(0)).toSet(), ph, reason: '$l $k');
        expect(_emoji.hasMatch(v), isFalse, reason: '$l $k');
      }
    }
  });

  test('informal Czech (tykání)', () {
    final formal = RegExp(r'\b(Vaše|Vaši|Vám|Vás|jste|Potřebujete|Můžete|Zarezervujte)\b');
    for (final e in all['cs']!.entries) {
      expect(formal.hasMatch(e.value), isFalse, reason: e.key);
    }
  });

  test('every key used by the Home v2 code is defined (here or already in the app)', () {
    final used = <String>{};
    final files = Directory('lib/features/home/v2').listSync().whereType<File>();
    for (final f in files) {
      for (final m in RegExp(r"""tr(?:Args)?\('([A-Za-z0-9]+)'""").allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    expect(used, isNotEmpty);
    for (final k in used) {
      final ok = all['cs']!.containsKey(k) || translations['cs']!.containsKey(k);
      expect(ok, isTrue, reason: 'missing key $k');
    }
  });
}
