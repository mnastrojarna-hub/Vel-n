// 5.0.2 výpůjčka jen výbavy — čisté výpočty objednávky (zrcadlo webu
// js/gear-rental.js: nacenění kompletů, rozsah samoobsluhy, sklad, kalendář).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/gear_rental/gear_contract.dart';
import 'package:motogo_app/features/gear_rental/gear_offer_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_quote.dart';

const _sizes = ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL'];

final prices = <GearPrice>[
  const GearPrice(key: 'full', kind: 'set', label: 'Komplet', includes: ['helmet', 'jacket', 'pants', 'gloves', 'boots'], perDay: 590),
  const GearPrice(key: 'noboots', kind: 'set', label: 'Komplet bez bot', includes: ['helmet', 'jacket', 'pants', 'gloves'], perDay: 490),
  const GearPrice(key: 'pricey', kind: 'set', label: 'Dražší komplet', includes: ['helmet', 'gloves'], perDay: 300),
  const GearPrice(key: 'helmet', kind: 'item', label: 'Helma', sizes: _sizes, perDay: 150),
  const GearPrice(key: 'jacket', kind: 'item', label: 'Bunda', sizes: _sizes, perDay: 200),
  const GearPrice(key: 'pants', kind: 'item', label: 'Kalhoty', sizes: _sizes, perDay: 150),
  const GearPrice(key: 'gloves', kind: 'item', label: 'Rukavice', sizes: _sizes, perDay: 50),
  const GearPrice(key: 'boots', kind: 'item', label: 'Boty', sizes: ['40', '41', '42', '43'], perDay: 100),
];

void main() {
  group('gearQuote (SQL _gear_rental_quote)', () {
    test('biggest set wins, rest per item, save = items − per day', () {
      final q = gearQuote(prices, {'helmet': 'M', 'jacket': 'L', 'pants': 'L', 'gloves': 'M', 'boots': '43'});
      expect(q.lines.map((l) => l.key), ['full']);
      expect(q.perDay, 590);
      expect(q.save, 650 - 590);
    });

    test('set without boots + boots item when boots are not complete set', () {
      final q = gearQuote(prices, {'helmet': '', 'jacket': '', 'pants': '', 'gloves': ''});
      expect(q.lines.map((l) => l.key), ['noboots']);
      expect(q.perDay, 490);
    });

    test('a set is used only when cheaper than its items', () {
      // pricey (300) > helmet + gloves (200) → per item
      final q = gearQuote(prices, {'helmet': 'M', 'gloves': 'M'});
      expect(q.lines.map((l) => l.key), ['helmet', 'gloves']);
      expect(q.perDay, 200);
      expect(q.save, 0);
    });

    test('set button is pressed only when exactly its items are selected', () {
      final s = prices.firstWhere((p) => p.key == 'noboots');
      expect(gearSetOn(s, prices, {'helmet': '', 'jacket': '', 'pants': '', 'gloves': ''}), isTrue);
      expect(gearSetOn(s, prices, {'helmet': '', 'jacket': '', 'pants': '', 'gloves': '', 'boots': ''}), isFalse);
    });
  });

  group('sizes', () {
    final helmet = prices.firstWhere((p) => p.key == 'helmet');
    final jacket = prices.firstWhere((p) => p.key == 'jacket');
    test('self-service caps adult sizes like the kiosk', () {
      expect(gearSizesFor(helmet, true), ['S', 'M', 'L', 'XL', '2XL', '3XL']);
      expect(gearSizesFor(jacket, true), ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL', '4XL']);
      expect(gearSizesFor(jacket, false), _sizes);
    });

    test('stock: tracked type only sizes with count > 0, XXL = 2XL, untracked free', () {
      final avail = {
        'enabled': true,
        'sizes': {
          'jacket': {'M': 0, 'XXL': 2},
        },
      };
      expect(gearSizeFree(avail, 'jacket', 'M'), isFalse);
      expect(gearSizeFree(avail, 'jacket', '2XL'), isTrue);
      expect(gearSizeFree(avail, 'jacket', 'L'), isFalse);
      expect(gearSizeFree(avail, 'helmet', 'L'), isTrue);
      expect(gearSizeFree(null, 'jacket', 'M'), isTrue);
    });

    test('prune clears a size that is no longer offered and reports sold-out ones', () {
      final avail = {
        'enabled': true,
        'sizes': {
          'jacket': {'M': 0},
        },
      };
      final (sel, dropped) = gearPrune(prices, {'jacket': 'M', 'helmet': 'XS'}, true, avail);
      expect(sel, {'jacket': '', 'helmet': ''});
      expect(dropped, [('M', 'Bunda')]);
    });

    test('complete needs branch, dates, items and every size', () {
      final d = DateTime(2026, 12, 1);
      expect(gearComplete(prices, {'helmet': 'M'}, hasBranch: true, start: d, end: d), isTrue);
      expect(gearComplete(prices, {'helmet': ''}, hasBranch: true, start: d, end: d), isFalse);
      expect(gearComplete(prices, {'helmet': 'M'}, hasBranch: false, start: d, end: d), isFalse);
      expect(gearComplete(prices, const {}, hasBranch: true, start: d, end: d), isFalse);
    });
  });

  group('calendar', () {
    final today = DateTime(2026, 11, 19);
    final closures = [GearClosure('b1', DateTime(2026, 12, 24), DateTime(2026, 12, 26))];
    GearDay st(DateTime d, {String? b = 'b1'}) =>
        gearDayState(d, today: today, maxAhead: 30, closures: closures, branchId: b);

    test('past / free / beyond max_ahead / closed branch', () {
      expect(st(DateTime(2026, 11, 18)), GearDay.past);
      expect(st(today), GearDay.free);
      expect(st(DateTime(2026, 12, 19)), GearDay.free);
      expect(st(DateTime(2026, 12, 20)), GearDay.busy);
    });

    test('closures only for the chosen branch', () {
      final c = [GearClosure('b1', DateTime(2026, 11, 25), DateTime(2026, 11, 26))];
      expect(gearDayState(DateTime(2026, 11, 25), today: today, maxAhead: 400, closures: c, branchId: 'b1'), GearDay.busy);
      expect(gearDayState(DateTime(2026, 11, 25), today: today, maxAhead: 400, closures: c, branchId: 'b2'), GearDay.free);
      expect(gearRangeOk(DateTime(2026, 11, 24), DateTime(2026, 11, 27), today: today, maxAhead: 400, closures: c, branchId: 'b1'), isFalse);
      expect(gearRangeOk(DateTime(2026, 11, 20), DateTime(2026, 11, 24), today: today, maxAhead: 400, closures: c, branchId: 'b1'), isTrue);
    });

    test('day count is inclusive and ISO dates', () {
      expect(gearCountDays(DateTime(2026, 11, 19), DateTime(2026, 11, 19)), 1);
      expect(gearCountDays(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 3);
      expect(gearIso(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('branches and entry gate', () {
    const cfg = GearRentalSettings(enabled: true, appVisible: true, selfServiceEnabled: false);
    final rows = [
      {'id': 'm', 'name': 'MotoGo24 Mezná', 'address': 'Mezná 9', 'city': 'Mezná', 'type': 'obslužná', 'is_open': true},
      {'id': 'v', 'name': 'MotoGo24 Velké Němčice', 'type': 'samoobslužná', 'is_open': true},
      {'id': 'x', 'name': 'Stará', 'active': false, 'is_open': true},
    ];

    test('name without prefix, address joined, self-service only when enabled, inactive skipped', () {
      final b = gearBranchesFrom(rows, cfg);
      expect(b.map((e) => e.id), ['m']);
      expect(b.first.name, 'Mezná');
      expect(b.first.address, 'Mezná 9, Mezná');
      final b2 = gearBranchesFrom(rows, const GearRentalSettings(selfServiceEnabled: true));
      expect(b2.map((e) => e.id), ['m', 'v']);
      expect(b2.last.self, isTrue);
    });

    test('settings parse + clamp like the web', () {
      final s = GearRentalSettings.fromJson({'enabled': true, 'app_visible': true, 'max_days': 0, 'max_ahead_days': 5000});
      expect(s.appVisible, isTrue);
      expect(s.maxDays, 1);
      expect(s.maxAheadDays, 800);
      expect(const GearRentalSettings().appVisible, isFalse);
    });

    test('entry: enabled && app_visible && prices && a branch open today', () {
      final today = DateTime(2026, 11, 19);
      final br = gearBranchesFrom(rows, cfg);
      expect(gearEntryVisible(cfg, prices, br, const [], today), isTrue);
      expect(gearEntryVisible(const GearRentalSettings(enabled: true, appVisible: false), prices, br, const [], today), isFalse);
      expect(gearEntryVisible(const GearRentalSettings(enabled: false, appVisible: true), prices, br, const [], today), isFalse);
      expect(gearEntryVisible(cfg, const [], br, const [], today), isFalse);
      expect(gearEntryVisible(cfg, prices, const [], const [], today), isFalse);
      final closedToday = [GearClosure('m', DateTime(2026, 11, 1), DateTime(2026, 11, 30))];
      expect(gearEntryVisible(cfg, prices, br, closedToday, today), isFalse);
    });
  });
}
