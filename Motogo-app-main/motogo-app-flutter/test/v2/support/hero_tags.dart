// Shared-element rule (design M1): ONE tagged source per route — two Heroes
// with the same tag on one page break the flight (Flutter asserts).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails when two onstage Heroes inside the same route share a tag.
void expectUniqueHeroTags(WidgetTester tester) {
  final byRoute = <Object?, Set<Object>>{};
  for (final e in find.byType(Hero).evaluate()) {
    final tag = (e.widget as Hero).tag;
    final route = ModalRoute.of(e);
    final seen = byRoute.putIfAbsent(route, () => <Object>{});
    expect(seen.add(tag), isTrue, reason: 'Hero tag "$tag" used twice on one route');
  }
}
