// verify:render static i18n gate: every literal key the v2 UI asks for
// (`tr('…')`, `trArgs('…'`) in lib/core/v2, lib/features/*/v2 and the
// v2 branches of seams exists in ALL 8 languages (no silent fallback to
// English / Czech / the raw key).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _call = RegExp(r'''\.tr(?:Args)?\(\s*['"]([A-Za-z0-9_]+)['"]''');

Iterable<File> _v2Sources() sync* {
  final roots = [Directory('lib/core/v2')];
  for (final d in Directory('lib/features').listSync().whereType<Directory>()) {
    final v2 = Directory('${d.path}/v2');
    if (v2.existsSync()) roots.add(v2);
  }
  for (final r in roots) {
    yield* r.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  }
}

void main() {
  test('every literal v2 translation key exists in all 8 languages', () {
    final missing = <String>[];
    for (final f in _v2Sources()) {
      for (final m in _call.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!;
        final gaps = [for (final l in _langs) if ((translations[l]?[k] ?? '').trim().isEmpty) l];
        if (gaps.isNotEmpty) missing.add('${f.path}: $k → ${gaps.join(',')}');
      }
    }
    // Keys held in lists / maps / ternaries ('…' literals that ARE keys).
    final lit = RegExp(r"'([a-z][A-Za-z0-9]{3,})'");
    final known = {...?translations['cs']?.keys, ...?translations['en']?.keys};
    for (final f in _v2Sources()) {
      for (final m in lit.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!;
        if (!known.contains(k) || !RegExp('[A-Z]').hasMatch(k)) continue;
        final gaps = [for (final l in _langs) if ((translations[l]?[k] ?? '').trim().isEmpty) l];
        if (gaps.isNotEmpty) missing.add('${f.path}: $k → ${gaps.join(',')}');
      }
    }
    final out = Platform.environment['MG_VERIFY_REPORT'];
    if (out != null && out.isNotEmpty) {
      Directory(out).createSync(recursive: true);
      File('$out/i18n_static.txt').writeAsStringSync(missing.toSet().join('\n'));
    }
    expect(missing.toSet(), isEmpty);
  });
}
