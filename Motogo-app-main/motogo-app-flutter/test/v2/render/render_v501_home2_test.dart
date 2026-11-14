// verify:render — Home v5.0.1 offer card, repair round 2: no dates, dates,
// nothing free (booked out / closed) and the bike calendar that
// "Vybrat jiný termín" opens (nothing ticked, legend, jump to the first
// free day). Renders only with MG_VERIFY_RENDER=1 (render harness).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart' show mockPathProvider;
import 'render_harness.dart';

Future<void> _openOther(WidgetTester tester) async {
  final label = t(tester.element(find.byType(HomeScreenV2))).tr('v2HomeFnPickOther');
  final cta = find.byWidgetPredicate((w) => w is MgCta && w.label == label);
  await tester.ensureVisible(cta);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(cta);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  final c = homeCases();
  renderMatrix([
    for (final s in ['s0', 's0-dates', 's0-nonefree', 's0-closed'])
      RenderCase('home2', 'home', s, () => const HomeScreenV2(), c[s]!),
    RenderCase('home2', 'sheet', 'nonefree', () => const HomeScreenV2(), c['s0-nonefree']!, after: _openOther),
    RenderCase('home2', 'sheet', 'closed', () => const HomeScreenV2(), c['s0-closed']!, after: _openOther),
  ], setUpAllExtra: () async => mockPathProvider());
}
