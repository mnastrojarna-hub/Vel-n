// FND-0: the ext_60 maps of the v2-everywhere run (one A/B pair per
// package) — same key set in all 8 languages, own prefix, no collision with
// any other translation file, no emoji, tykání in Czech, same placeholders.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_core_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_core_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_shell_home_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_shell_home_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_catalog_booking_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_catalog_booking_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_res_profile_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_res_profile_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_pay_shop_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_pay_shop_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_auth_sos_misc_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_auth_sos_misc_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_routes_rides_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_60_v2_ux_routes_rides_b.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _ph = RegExp(r'\{[a-zA-Z]+\}');
final _emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true);
final _formal = RegExp(r'\b(Vyberte|Klikněte|Zadejte|Vaše|Vás|jste)\b');

final _maps = <(String, String, Map<String, Map<String, String>>)>[
  ('translations_ext_60_v2_ux_core_a.dart', 'v2UxCore', translationsExt60V2UxCoreA),
  ('translations_ext_60_v2_ux_core_b.dart', 'v2UxCore', translationsExt60V2UxCoreB),
  ('translations_ext_60_v2_ux_shell_home_a.dart', 'v2UxSh', translationsExt60V2UxShellHomeA),
  ('translations_ext_60_v2_ux_shell_home_b.dart', 'v2UxSh', translationsExt60V2UxShellHomeB),
  ('translations_ext_60_v2_ux_catalog_booking_a.dart', 'v2UxCb', translationsExt60V2UxCatalogBookingA),
  ('translations_ext_60_v2_ux_catalog_booking_b.dart', 'v2UxCb', translationsExt60V2UxCatalogBookingB),
  ('translations_ext_60_v2_ux_res_profile_a.dart', 'v2UxRp', translationsExt60V2UxResProfileA),
  ('translations_ext_60_v2_ux_res_profile_b.dart', 'v2UxRp', translationsExt60V2UxResProfileB),
  ('translations_ext_60_v2_ux_pay_shop_a.dart', 'v2UxPs', translationsExt60V2UxPayShopA),
  ('translations_ext_60_v2_ux_pay_shop_b.dart', 'v2UxPs', translationsExt60V2UxPayShopB),
  ('translations_ext_60_v2_ux_auth_sos_misc_a.dart', 'v2UxAsm', translationsExt60V2UxAuthSosMiscA),
  ('translations_ext_60_v2_ux_auth_sos_misc_b.dart', 'v2UxAsm', translationsExt60V2UxAuthSosMiscB),
  ('translations_ext_60_v2_ux_routes_rides_a.dart', 'v2UxRr', translationsExt60V2UxRoutesRidesA),
  ('translations_ext_60_v2_ux_routes_rides_b.dart', 'v2UxRr', translationsExt60V2UxRoutesRidesB),
];

void main() {
  test('14 maps, all registered, 8 languages each', () {
    expect(_maps.length, 14);
    for (final (file, _, m) in _maps) {
      expect(m.keys.toSet(), _langs.toSet(), reason: file);
      for (final l in _langs) {
        for (final e in m[l]!.entries) {
          expect(translations[l]![e.key], e.value, reason: '$file $l ${e.key} not registered');
        }
      }
    }
  });

  test('identical key sets, own prefix, placeholders, no emoji, tykání', () {
    for (final (file, prefix, m) in _maps) {
      final keys = m['cs']!.keys.toSet();
      for (final l in _langs) {
        expect(m[l]!.keys.toSet(), keys, reason: '$file $l keys');
      }
      for (final k in keys) {
        expect(k.startsWith(prefix), isTrue, reason: '$file $k prefix');
        final ph = _ph.allMatches(m['cs']![k]!).map((x) => x.group(0)).toSet();
        for (final l in _langs) {
          final v = m[l]![k]!;
          expect(v.trim(), isNotEmpty, reason: '$file $l $k');
          expect(_ph.allMatches(v).map((x) => x.group(0)).toSet(), ph, reason: '$file $l $k placeholders');
          expect(_emoji.hasMatch(v), isFalse, reason: '$file $l $k emoji');
        }
        expect(_formal.hasMatch(m['cs']![k]!), isFalse, reason: '$file $k vykání');
      }
    }
  });

  test('no ext_60 key collides with another file or another ext_60 map', () {
    final mine = <String, String>{};
    for (final (file, _, m) in _maps) {
      for (final k in m['cs']!.keys) {
        expect(mine.containsKey(k), isFalse, reason: '$k in $file and ${mine[k]}');
        mine[k] = file;
      }
    }
    final keyRe = RegExp(r"^\s+'([A-Za-z0-9_]+)':\s", multiLine: true);
    for (final f in Directory('lib/core/i18n').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('translations_ext_60_')) continue;
      for (final x in keyRe.allMatches(f.readAsStringSync())) {
        expect(mine.containsKey(x.group(1)), isFalse, reason: '${x.group(1)} also in $name');
      }
    }
  });

  test('core offline text is gender-neutral and set', () {
    expect(translations['cs']!['v2UxCoreOffline'], 'Telefon je offline. Zapni data nebo Wi-Fi a zkus to znovu.');
    expect(translations['cs']!['v2UxCoreAiCoach'], 'Zeptej se kdykoli. Jsme tu pro tebe.');
  });
}
