// 5.0.2 „Půjčit samotnou výbavu“ na Domů (majitel 2026-11-19): řádek ve
// stylu „Spočítat cenu“ / „Zaznamenat jízdu“ jen při enabled && app_visible
// a otevřené pobočce; starý vzhled stejná podmínka, styl karty Domů.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/widgets/mg_icon_tile.dart';
import 'package:motogo_app/features/gear_rental/gear_contract.dart';
import 'package:motogo_app/features/gear_rental/gear_offer_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_quote.dart';
import 'package:motogo_app/features/home/v2/home_gear_row_v2.dart';
import 'package:motogo_app/features/home/widgets/home_gear_row.dart';

import '../support/v2_harness.dart';

const _prices = [GearPrice(key: 'helmet', kind: 'item', label: 'Helma', sizes: ['M'], perDay: 120)];
const _branches = [GearBranch(id: 'm', name: 'Mezná')];

List<Override> gate({
  bool enabled = true,
  bool appVisible = true,
  List<GearBranch> branches = _branches,
  List<GearClosure> closures = const [],
}) =>
    [
      gearRentalSettingsProvider.overrideWith((ref) async => GearRentalSettings(enabled: enabled, appVisible: appVisible)),
      gearPricesProvider.overrideWith((ref) async => _prices),
      gearBranchesProvider.overrideWith((ref) async => branches),
      gearClosuresProvider.overrideWith((ref) async => closures),
    ];

Future<void> pumpRow(WidgetTester tester, {required bool v2, required List<Override> overrides}) async {
  await pumpV2(tester, Column(children: [v2 ? const HomeGearRowV2() : const HomeGearRow()]), v2: v2, overrides: overrides);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(loadMontserrat);

  group('v2 Home row', () {
    testWidgets('shown with enabled + app_visible + open branch: dark tile, texts', (tester) async {
      await pumpRow(tester, v2: true, overrides: gate());
      expect(find.byKey(const ValueKey('home-gear-row')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('home-gear-row')), matching: find.byType(MgIconTileDark)),
          findsOneWidget);
      expect(find.text('Půjčit samotnou výbavu'), findsOneWidget);
      expect(find.text('Helma, bunda, kalhoty, rukavice i boty – bez motorky'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden by default (app_visible false — live value 19 Nov)', (tester) async {
      await pumpRow(tester, v2: true, overrides: gate(appVisible: false));
      expect(find.byKey(const ValueKey('home-gear-row')), findsNothing);
    });

    testWidgets('hidden when the service is off', (tester) async {
      await pumpRow(tester, v2: true, overrides: gate(enabled: false));
      expect(find.byKey(const ValueKey('home-gear-row')), findsNothing);
    });

    testWidgets('hidden without an open branch / when closed today', (tester) async {
      await pumpRow(tester, v2: true, overrides: gate(branches: const []));
      expect(find.byKey(const ValueKey('home-gear-row')), findsNothing);
      final today = gearPragueToday();
      await pumpRow(tester,
          v2: true,
          overrides: gate(closures: [GearClosure('m', gearAddDays(today, -1), gearAddDays(today, 1))]));
      expect(find.byKey(const ValueKey('home-gear-row')), findsNothing);
    });

    testWidgets('hidden while loading', (tester) async {
      await pumpRow(tester, v2: true, overrides: [gearRentEntryProvider.overrideWith((ref) => Future<bool>.delayed(const Duration(hours: 1), () => true))]);
      expect(find.byKey(const ValueKey('home-gear-row')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(hours: 2));
    });
  });

  group('old-look Home row', () {
    testWidgets('shown under the same gate, card style with chevron', (tester) async {
      await pumpRow(tester, v2: false, overrides: gate());
      expect(find.byKey(const ValueKey('home-gear-row-old')), findsOneWidget);
      expect(find.byIcon(Icons.checkroom), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('Půjčit samotnou výbavu'), findsOneWidget);
    });

    testWidgets('hidden when app_visible is false', (tester) async {
      await pumpRow(tester, v2: false, overrides: gate(appVisible: false));
      expect(find.byKey(const ValueKey('home-gear-row-old')), findsNothing);
    });
  });
}
