// Úprava zaplacené rezervace přímým zápisem: pojistka DB může termín,
// motorku a cenu tiše ponechat. Appka pak nesmí tvrdit „uloženo“ ani volat
// vratku — editWriteApplied to pozná z přenačteného řádku.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations_ext_40_refix_a.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/features/reservations/edit_write_check.dart';

void main() {
  const original = {'start_date': '2026-12-01', 'end_date': '2026-12-03', 'moto_id': 'm1', 'total_price': 6000};

  test('row equals the wanted values → true', () {
    final changes = {'start_date': '2026-12-01', 'end_date': '2026-12-04', 'total_price': 5800.0, 'pickup_method': 'store'};
    final row = {'start_date': '2026-12-01', 'end_date': '2026-12-04T00:00:00+00:00', 'moto_id': 'm1', 'total_price': 5800.2};
    expect(editWriteApplied(row, changes, original), isTrue);
  });

  test('more days + lower total, row still original (guard pinned it) → false', () {
    final changes = {'start_date': '2026-12-01', 'end_date': '2026-12-04', 'total_price': 5500, 'delivery_fee': 0};
    final row = {'start_date': '2026-12-01', 'end_date': '2026-12-03', 'moto_id': 'm1', 'total_price': 6000};
    expect(editWriteApplied(row, changes, original), isFalse);
  });

  test('a pinned bike → false', () {
    final changes = {'moto_id': 'm2', 'total_price': 5000};
    final row = {'start_date': '2026-12-01', 'end_date': '2026-12-03', 'moto_id': 'm1', 'total_price': 6000};
    expect(editWriteApplied(row, changes, original), isFalse);
    expect(editWriteApplied({...row, 'moto_id': 'm2', 'total_price': 5000}, changes, original), isTrue);
  });

  test('nothing distinguishing → null', () {
    final row = {'start_date': '2026-12-01', 'end_date': '2026-12-03', 'moto_id': 'm1', 'total_price': 6000};
    expect(editWriteApplied(row, {'pickup_method': 'delivery', 'pickup_address': 'Husova 5'}, original), isNull);
    // Same values as before do not distinguish either (incl. price within 0.5).
    expect(editWriteApplied(row, {'start_date': '2026-12-01', 'total_price': 6000.4}, original), isNull);
  });

  test('mixed or foreign state cannot be told → null', () {
    final changes = {'end_date': '2026-12-04', 'total_price': 5500};
    expect(editWriteApplied({'end_date': '2026-12-04', 'total_price': 6000}, changes, original), isNull);
    expect(editWriteApplied({'end_date': '2026-12-09', 'total_price': 9000}, changes, original), isNull);
  });

  test('fxEditPinned text: cs + en here, all 8 languages registered', () {
    expect(translationsExt40RefixA['cs']!['fxEditPinned'], isNotEmpty);
    expect(translationsExt40RefixA['en']!['fxEditPinned'], isNotEmpty);
    for (final l in ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
      expect(translations[l]?['fxEditPinned'], isNotNull, reason: l);
      expect(translations[l]!['fxEditPinned']!.trim(), isNotEmpty, reason: l);
    }
  });
}
