// verify:render cases — Home v2: every state of home_test.dart (funnel,
// booking cards, recording, review card, loading / errors), the opened
// filter + the date sheet (empty / picked range) and the club rules sheet.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_club_card_v2.dart';
import 'package:motogo_app/features/home/v2/home_date_sheet_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart';
import 'cases_core.dart' show launcher, tapOpen;
import 'render_harness.dart';

List<RenderCase> homeRenderCases() => [
      for (final e in homeCases().entries)
        RenderCase('home', 'home', e.key, () => const HomeScreenV2(), e.value,
            loading: e.key.contains('loading')),
      RenderCase('home', 'sheet', 'dates_empty',
          () => launcher((c) => showHomeDateSheet(c, applyLabel: t(c).tr('v2HomeDateShow'))), () => homeOverrides(),
          after: tapOpen),
      RenderCase(
          'home',
          'sheet',
          'dates_range',
          () => launcher((c) => showHomeDateSheet(c,
              initial: FunnelRange(day(9), day(12)), applyLabel: t(c).tr('v2HomeDateShow'), onClear: () {})),
          () => homeOverrides(),
          after: tapOpen),
      RenderCase('home', 'sheet', 'club_rules', () => launcher(showClubRulesSheet), () => homeOverrides(), after: tapOpen),
      // lookonly-fix:core — the old Domů filter (collapsed by default) opened:
      // TERMÍN + calendar + the panel content, with a branch and a filter set.
      RenderCase('home', 'home', 'filter_open', () => const HomeScreenV2(), homeCases()['s6']!, after: _openFilter),
    ];

Future<void> _openFilter(WidgetTester tester) async {
  final title = t(tester.element(find.byType(HomeScreenV2))).tr('homeFilterTitle');
  final f = find.text(title);
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}
