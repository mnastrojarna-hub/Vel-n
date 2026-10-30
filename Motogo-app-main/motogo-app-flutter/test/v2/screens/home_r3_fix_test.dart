// fix:home r3 — compact preset dates (board: no weekday, "16.–18. 10.",
// breaks only after the dash; the screen reader still hears the days);
// the centred funnel bike resets only when the shown RANGE changes (the
// same weekend "given" by a card tap, or a new day with the same range,
// keep it — photo = "n / m" = REZERVOVAT).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/home/v2/funnel_dates.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';

import '../support/fakes_home.dart' show day;

const _nb = ' ';

void main() {
  AppTranslations tr(String lang) => AppTranslations(lang);

  test('compact preset range per language (no weekday, U+00A0 inside a date)', () {
    final s = DateTime(2026, 10, 16), e = DateTime(2026, 10, 18);
    final a = DateTime(2026, 10, 30), b = DateTime(2026, 11, 1);
    expect(funnelRangeShort(tr('cs'), s, e), '16.–18.${_nb}10.');
    expect(funnelRangeShort(tr('cs'), a, b), '30.${_nb}10.$_nb– 1.${_nb}11.');
    expect(funnelRangeShort(tr('de'), s, e), '16.–18.10.');
    expect(funnelRangeShort(tr('en'), s, e), '16–18/10');
    expect(funnelRangeShort(tr('en'), a, b), '30/10$_nb– 1/11');
    expect(funnelRangeShort(tr('pl'), s, e), '16–18.10');
    expect(funnelRangeShort(tr('uk'), s, e), '16–18.10');
    // "16-10": a hyphen beside the dash would read as one number → full dates.
    expect(funnelRangeShort(tr('nl'), s, e), '16-10$_nb– 18-10');
    expect(funnelRangeShort(tr('cs'), s, s), '16.${_nb}10.');
    for (final l in ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
      final txt = funnelRangeShort(tr(l), a, b);
      expect(txt.contains(' '), isTrue, reason: '$l: one break point, after the dash');
      expect(txt.indexOf(' '), txt.lastIndexOf(' '), reason: '$l: only one ordinary space');
      expect(txt, isNot(contains(tr(l).tr('v2CalWdAbbr5'))), reason: '$l: no weekday');
    }
  });

  test('the centred bike survives the same range given, resets on other dates', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final sub = c.listen(funnelCenterProvider, (_, __) {});
    addTearDown(sub.close);
    final p = funnelPresets(c.read(funnelTodayProvider));
    c.read(funnelCenterProvider.notifier).state = 1;
    // Nothing given → the nearest weekend; now the same weekend is given.
    c.read(funnelGivenProvider.notifier).state = p.$1;
    expect(c.read(funnelSelectionProvider).given, p.$1);
    expect(c.read(funnelCenterProvider), 1, reason: 'same range = same carousel');
    // Other dates → their first bike.
    c.read(funnelGivenProvider.notifier).state = FunnelRange(day(9), day(12));
    expect(c.read(funnelCenterProvider), 0);
    expect(c.read(funnelRangeProvider), FunnelRange(day(9), day(12)));
    // A new day on which the given range is still the same keeps the bike.
    c.read(funnelCenterProvider.notifier).state = 1;
    c.read(funnelTodayProvider.notifier).state = day(1);
    expect(c.read(funnelCenterProvider), 1);
  });
}
