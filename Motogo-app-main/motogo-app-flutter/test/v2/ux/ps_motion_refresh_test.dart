// pay_shop PS-20 / 23: the bag badge bumps when the count rises (nothing
// under reduced motion); pull-to-refresh on the e-shop grid and on payment
// methods runs the screen's existing retry (provider reload).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/payment/payment_methods_screen.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:motogo_app/features/shop/shop_screen.dart';
import 'package:motogo_app/features/shop/v2/shop_view_v2.dart';

import '../render/cases_ux_pay_shop.dart' show kPsCards, kPsProducts, psShopOverrides;
import '../support/ps_harness.dart';

class _Bag extends StatefulWidget {
  const _Bag();
  @override
  State<_Bag> createState() => _BagState();
}

class _BagState extends State<_Bag> {
  int count = 1;
  void add() => setState(() => count++);
  @override
  Widget build(BuildContext context) => Center(child: ShopBagButtonV2(count: count, onTap: () {}));
}

double _scale(WidgetTester t) {
  final tr = find.descendant(of: find.byType(MgBump), matching: find.byType(Transform));
  if (tr.evaluate().isEmpty) return 1;
  return t.widget<Transform>(tr.first).transform.getMaxScaleOnAxis();
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets('bag badge bumps on add (reduced motion: $reduced → ${reduced ? 'static' : 'bump'})', (tester) async {
      await pumpPs(tester, const Material(child: _Bag()), reducedMotion: reduced);
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
      tester.state<_BagState>(find.byType(_Bag)).add();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      if (reduced) {
        expect(_scale(tester), 1);
      } else {
        expect(_scale(tester), greaterThan(1.05));
      }
      await tester.pumpAndSettle();
      expect(_scale(tester), closeTo(1, 0.001));
      expect(find.text('2'), findsOneWidget);
    });
  }

  testWidgets('shop grid: pull-to-refresh reloads the products (the existing retry)', (tester) async {
    var loads = 0;
    final router = await pumpPs(tester, const ShopScreen(), overrides: [
      ...psShopOverrides(),
      productsProvider.overrideWith((ref) async {
        loads++;
        return kPsProducts;
      }),
    ]);
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(loads, 2);
    await psLeaveRoute(tester, router);
  });

  testWidgets('payment methods: pull-to-refresh reloads the cards', (tester) async {
    var loads = 0;
    final router = await pumpPs(tester, const PaymentMethodsScreen(), overrides: [
      ...psShopOverrides(),
      paymentMethodsProvider.overrideWith((ref) async {
        loads++;
        return kPsCards;
      }),
    ]);
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(loads, 2);
    await psLeaveRoute(tester, router);
  });
}
