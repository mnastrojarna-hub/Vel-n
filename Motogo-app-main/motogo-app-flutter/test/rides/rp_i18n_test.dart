// Texty záznamu jízd `rp*` (SPEC §12): každý klíč v 8 jazycích, neprázdný,
// stejné zástupné symboly jako čeština, žádný `v2` klíč, tykání; tvary
// množného čísla (cs 1/2/5/21, pl 2/5/12/22, uk 1/3/11/21); klíče, které
// používá logika záznamníku (LOGIC_API §6), existují.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_47_rides.dart';
import 'package:motogo_app/features/routes/ride_live_stats.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _ph = RegExp(r'\{[a-zA-Z]+\}');

Set<String> _phs(String s) => _ph.allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  final keys = translationsExt47Rides['cs']!.keys.toSet();

  test('ext_47 je zaregistrovaný v translations.dart', () {
    expect(keys.length, greaterThan(100));
    for (final k in keys) {
      expect(translations['cs']![k], translationsExt47Rides['cs']![k], reason: k);
    }
  });

  test('každý klíč ve všech 8 jazycích, neprázdný, stejné zástupné symboly', () {
    for (final l in _langs) {
      expect(translationsExt47Rides[l]!.keys.toSet(), keys, reason: 'sada klíčů $l');
    }
    for (final k in keys) {
      final ph = _phs(translationsExt47Rides['cs']![k]!);
      for (final l in _langs) {
        final v = translationsExt47Rides[l]![k];
        expect(v, isNotNull, reason: '$l $k');
        expect(v!.trim(), isNotEmpty, reason: '$l $k');
        expect(_phs(v), ph, reason: '$l $k zástupné symboly');
      }
    }
  });

  test('jen klíče rp*, žádné v2 (to hlídá i18n_v2_test)', () {
    for (final k in keys) {
      expect(k.startsWith('rp'), isTrue, reason: k);
    }
    for (final f in Directory('lib/core/i18n').listSync().whereType<File>()) {
      if (!f.path.contains('translations_ext_47_')) continue;
      expect(RegExp(r"'v2[A-Z]\w*':").hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('čeština tyká', () {
    final formal = RegExp(r'\b(Vaše|Váš|Vám|Vás|jste|Potřebujete|Můžete|Klepněte|Vyberte|Zkontrolujte)\b');
    for (final k in keys) {
      expect(formal.hasMatch(translationsExt47Rides['cs']![k]!), isFalse, reason: k);
    }
  });

  test('klíče, které používá logika záznamníku, existují', () {
    const logic = [
      'rpNotifTitle', 'rpNotifDefault', 'rpNotifRidingTitle', 'rpNotifRiding', 'rpNotifArmedTitle',
      'rpNotifArmed', 'rpNotifPausedTitle', 'rpNotifPaused', 'rpNotifIdleTitle', 'rpNotifIdleText',
      'rpTripContinuedNew', 'rpTripContinuedNewOld', 'rpOwnSavedForRental', 'rpDaysOne', 'rpDaysFew',
      'rpDaysMany', 'rpRidesOne', 'rpRidesFew', 'rpRidesMany', 'rpTripRental', 'rpTripDefault',
      'rpTripPartial', 'rpTripUnavailable', 'rpTripFailed',
    ];
    for (final k in logic) {
      expect(keys, contains(k));
    }
  });

  test('množné číslo dnů a jízd', () {
    String d(String l, int n) => rideDaysLabel(n, AppTranslations(l));
    String r(String l, int n) => rideRidesLabel(n, AppTranslations(l));
    expect([d('cs', 1), d('cs', 2), d('cs', 5), d('cs', 21)], ['1 den', '2 dny', '5 dní', '21 dní']);
    expect([r('cs', 1), r('cs', 3), r('cs', 7)], ['1 jízda', '3 jízdy', '7 jízd']);
    expect([d('pl', 2), d('pl', 5), d('pl', 12), d('pl', 22)], ['2 dni', '5 dni', '12 dni', '22 dni']);
    expect([r('pl', 2), r('pl', 5), r('pl', 12), r('pl', 22)],
        ['2 przejazdy', '5 przejazdów', '12 przejazdów', '22 przejazdy']);
    expect([d('uk', 1), d('uk', 3), d('uk', 11), d('uk', 21)], ['1 день', '3 дні', '11 днів', '21 день']);
    expect([d('en', 1), d('en', 2), d('fr', 0), d('fr', 1), d('fr', 2)],
        ['1 day', '2 days', '0 jour', '1 jour', '2 jours']);
  });
}
