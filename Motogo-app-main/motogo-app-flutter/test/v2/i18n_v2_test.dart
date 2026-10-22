// v2 strings (PLAN §4.2): every key in all 8 languages, non-empty, same
// placeholders, `v2` prefix only in the ext_5* files (no override of old
// texts), no emoji, informal Czech.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _placeholder = RegExp(r'\{[a-zA-Z]+\}');
final _emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}]', unicode: true);

/// Keys defined in the v2 ext files (parsed from source, all languages).
Map<String, Set<String>> _v2Files() {
  final dir = Directory('lib/core/i18n');
  final out = <String, Set<String>>{};
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!RegExp(r'^translations_ext_5\d_').hasMatch(name)) continue;
    out[name] = RegExp(r"^\s+'([A-Za-z0-9_]+)':\s", multiLine: true)
        .allMatches(f.readAsStringSync())
        .map((m) => m.group(1)!)
        .where((k) => !_langs.contains(k))
        .toSet();
  }
  return out;
}

void main() {
  final files = _v2Files();
  final v2Keys = files.values.expand((s) => s).toSet();

  test('there are v2 files and keys', () {
    expect(files, isNotEmpty);
    expect(v2Keys.length, greaterThan(100));
  });

  test('ext_5* files define only v2-prefixed keys', () {
    files.forEach((file, keys) {
      for (final k in keys) {
        expect(k.startsWith('v2'), isTrue, reason: '$file: $k');
      }
    });
  });

  test('no v2-prefixed key outside the ext_5* files', () {
    for (final f in Directory('lib/core/i18n').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (RegExp(r'^translations_ext_5\d_').hasMatch(name)) continue;
      expect(RegExp(r"'v2[A-Z]\w*':").hasMatch(f.readAsStringSync()), isFalse, reason: name);
    }
  });

  test('every v2 key in all 8 languages, non-empty, same placeholders, no emoji', () {
    for (final k in v2Keys) {
      final cs = translations['cs']![k];
      expect(cs, isNotNull, reason: 'cs $k (file registered in translations.dart?)');
      final ph = _placeholder.allMatches(cs!).map((m) => m.group(0)).toSet();
      for (final l in _langs) {
        final v = translations[l]![k];
        expect(v, isNotNull, reason: '$l $k');
        expect(v!.trim(), isNotEmpty, reason: '$l $k');
        expect(_placeholder.allMatches(v).map((m) => m.group(0)).toSet(), ph, reason: '$l $k placeholders');
        expect(_emoji.hasMatch(v), isFalse, reason: '$l $k has emoji');
      }
    }
  });

  test('Czech is informal (tykání)', () {
    final formal = RegExp(r'\b(Vaše|Váš|Vám|Vás|jste|Potřebujete|Můžete|Klepněte|Vyberte)\b');
    for (final k in v2Keys) {
      expect(formal.hasMatch(translations['cs']![k]!), isFalse, reason: k);
    }
  });
}
