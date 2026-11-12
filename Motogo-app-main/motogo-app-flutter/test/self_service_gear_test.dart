// Samoobslužná pobočka (zadání majitele 2026-10-10): helma S–3XL, bunda,
// kalhoty a rukavice nejvýš 4XL. Obsluhovaná pobočka = řady jako ve 4.1.3.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/self_service_gear.dart';

// Řady z booking_models.dart ve 4.1.3 (commit 70a94933) — opsané, ne importované.
const _base413 = {
  'helmet': ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'],
  'jacket': ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', '6XL'],
  'gloves': ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL'],
  'pants': ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', '6XL'],
  'boots': ['39', '40', '41', '42', '43', '44', '45', '46', '47', '48'],
};
const _kids413 = {
  'helmet': ['YM', 'XS', 'S'],
  'jacket': ['YM 4–6 let', 'Vesta 4–9 let'],
  'gloves': ['4–7 let', '8–12 let'],
  'pants': ['4–7 let', '7–9 let'],
  'boots': ['33', '35'],
};

void main() {
  test('helmet: XS and 4XL refused, S and 3XL allowed', () {
    expect(selfServiceSizeAllowed('helmet', 'XS'), isFalse);
    expect(selfServiceSizeAllowed('helmet', '4XL'), isFalse);
    expect(selfServiceSizeAllowed('helmet', 'S'), isTrue);
    expect(selfServiceSizeAllowed('helmet', '3XL'), isTrue);
  });

  test('jacket, pants, gloves: up to 4XL, no lower limit', () {
    for (final t in ['jacket', 'pants', 'gloves']) {
      expect(selfServiceSizeAllowed(t, '4XL'), isTrue, reason: t);
      expect(selfServiceSizeAllowed(t, '5XL'), isFalse, reason: t);
      expect(selfServiceSizeAllowed(t, '6XL'), isFalse, reason: t);
      expect(selfServiceSizeAllowed(t, 'XXS'), isTrue, reason: t);
    }
  });

  test('aliases, trimming and case', () {
    expect(selfServiceSizeAllowed('helmet', 'XXL'), selfServiceSizeAllowed('helmet', '2XL'));
    expect(selfServiceSizeAllowed('helmet', 'XXL'), isTrue);
    expect(selfServiceSizeAllowed('jacket', ' xxl '), isTrue);
    expect(selfServiceSizeAllowed('jacket', ' 5xl '), isFalse);
    expect(selfServiceSizeAllowed('helmet', 'xs'), isFalse);
  });

  test('unknown sizes pass: boot numbers, kids labels, empty, null', () {
    expect(selfServiceSizeAllowed('boots', '43'), isTrue);
    expect(selfServiceSizeAllowed('jacket', 'YM 4–6 let'), isTrue);
    expect(selfServiceSizeAllowed('helmet', ''), isTrue);
    expect(selfServiceSizeAllowed('helmet', null), isTrue);
  });

  test('staffed branch: the 4.1.3 lists unchanged', () {
    _base413.forEach((type, sizes) {
      expect(gearSizesFor(type, kids: false), sizes, reason: type);
      expect(gearSizesFor(type, kids: false, selfService: false), sizes, reason: type);
    });
  });

  test('self-service: an ordered subset of the 4.1.3 list', () {
    _base413.forEach((type, sizes) {
      final ss = gearSizesFor(type, kids: false, selfService: true);
      expect(ss, sizes.where(ss.contains).toList(), reason: type);
      expect(ss.every(sizes.contains), isTrue, reason: type);
    });
    expect(gearSizesFor('helmet', kids: false, selfService: true), ['S', 'M', 'L', 'XL', '2XL', '3XL']);
    expect(gearSizesFor('jacket', kids: false, selfService: true), ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL']);
    expect(gearSizesFor('gloves', kids: false, selfService: true), ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL']);
    expect(gearSizesFor('boots', kids: false, selfService: true), _base413['boots']);
  });

  test('kids ignore selfService', () {
    _kids413.forEach((type, sizes) {
      expect(gearSizesFor(type, kids: true), sizes, reason: type);
      expect(gearSizesFor(type, kids: true, selfService: true), sizes, reason: type);
    });
  });
}
