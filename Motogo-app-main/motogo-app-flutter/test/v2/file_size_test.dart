// CLAUDE.md rule 2 / PLAN §0.4.1: v2 files stay ≤ ~5 000 tokens
// (≤ 18 500 bytes) — split by widget instead of growing a file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 files ≤ 18 500 bytes', () {
    final roots = <Directory>[Directory('lib/core/v2')];
    final features = Directory('lib/features');
    if (features.existsSync()) {
      for (final d in features.listSync().whereType<Directory>()) {
        final v2 = Directory('${d.path}/v2');
        if (v2.existsSync()) roots.add(v2);
      }
    }
    final files = <File>[
      for (final r in roots) ...r.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')),
      ...Directory('lib/core/i18n')
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'translations_ext_5\d_[^/]*\.dart$').hasMatch(f.path)),
    ];
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(f.lengthSync(), lessThanOrEqualTo(18500), reason: f.path);
    }
  });
}
