// Docasny smoke test: import main.dart zkompiluje celou appku (vsechny
// dosazitelne knihovny) — overi upgrade pluginu bez Android SDK.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/main.dart' as app;

void main() {
  test('app main is compilable and importable', () {
    expect(app.main, isA<Function>());
  });
}
