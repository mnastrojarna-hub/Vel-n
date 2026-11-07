// pay_shop PS-05 / 06 / 13 / 14: card sheet chrome (the card field keeps
// its element while paying, ✕ locked), the payment error sheet (same
// results for every caller, swipe-down only when dismissible), the
// leave-payment T6 dialog (same return values), payment methods (no add
// on iOS, delete confirm in the v2 dialog).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/widgets/mg_dialog.dart';
import 'package:motogo_app/features/payment/payment_methods_screen.dart';
import 'package:motogo_app/features/payment/payment_ui_helpers.dart';
import 'package:motogo_app/features/payment/v2/card_sheet_v2.dart';
import 'package:motogo_app/features/payment/v2/error_sheet_v2.dart';
import 'package:motogo_app/features/payment/v2/payment_methods_view_v2.dart';
import 'package:motogo_app/features/payment/widgets/payment_error_sheet.dart';

import '../render/cases_ux_pay_shop.dart' show kPsCards, psShopOverrides;
import '../support/ps_harness.dart';
import '../support/v2_harness.dart' show pumpV2;

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool busy = false;
  int paid = 0;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: CardSheetV2(
          title: 'Zaplatit kartou',
          processing: busy,
          onClose: () {},
          cardField: const SizedBox(key: ValueKey('fake-card-field'), height: 40),
          payLabel: 'Zaplatit 100 Kč →',
          onPay: busy ? null : () => setState(() => paid++),
          note: busy ? 'Platba probíhá' : null,
          noteIsStatus: busy,
        ),
      );
}

void main() {
  testWidgets('card sheet: the field keeps ONE element idle ↔ paying; pay runs the given action', (tester) async {
    await pumpV2(tester, const _Host());
    final before = tester.element(find.byKey(const ValueKey('fake-card-field')));
    await tester.tap(find.text('Zaplatit 100 Kč →'));
    final host = tester.state<_HostState>(find.byType(_Host));
    expect(host.paid, 1);
    host.setState(() => host.busy = true);
    await tester.pump();
    expect(tester.element(find.byKey(const ValueKey('fake-card-field'))), same(before));
    expect(find.text('Platba probíhá'), findsOneWidget);
    host.setState(() => host.busy = false);
    await tester.pump();
    expect(tester.element(find.byKey(const ValueKey('fake-card-field'))), same(before));
  });

  testWidgets('error sheet: buttons pop then call the caller; ✕ in a terminal state = main action', (tester) async {
    await pumpPs(tester, const SizedBox.expand());
    var main = 0, second = 0;
    final ctx = tester.element(find.byType(SizedBox).first);
    PaymentErrorSheet.show(ctx,
        title: 'Platba neprošla', message: 'Banka ji nepotvrdila.', buttonLabel: 'Zkusit znovu',
        onButton: () => main++, secondaryLabel: 'Jinou kartou', onSecondary: () => second++);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentErrorSheetV2), findsOneWidget);
    await tester.tap(find.text('Jinou kartou'));
    await tester.pumpAndSettle();
    expect((main, second), (0, 1));
    expect(find.byType(PaymentErrorSheetV2), findsNothing);

    PaymentErrorSheet.show(ctx, title: 'Čas vypršel', message: 'x', buttonLabel: 'Do rezervace', onButton: () => main++, dismissible: false);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Čas vypršel'), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentErrorSheetV2), findsOneWidget, reason: 'terminal sheet ignores drags');
    await tester.tap(find.bySemanticsLabel('Zavřít').last);
    await tester.pumpAndSettle();
    expect(main, 1);
    expect(find.byType(PaymentErrorSheetV2), findsNothing);

    PaymentErrorSheet.show(ctx, title: 'Bez připojení', message: 'x', buttonLabel: 'OK', onButton: () => main++);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Bez připojení'), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentErrorSheetV2), findsNothing, reason: 'dismissible sheet: swipe down closes');
    expect(main, 1, reason: 'closing by swipe calls nothing');
  });

  testWidgets('leave dialog (T6): Odejít = true, Zůstat a počkat = false, scrim = stay', (tester) async {
    await pumpPs(tester, const SizedBox.expand());
    final ctx = tester.element(find.byType(SizedBox).first);
    Future<bool?> run(Future<void> Function() act) async {
      bool? out;
      confirmLeaveRunningPayment(ctx).then((v) => out = v);
      await tester.pumpAndSettle();
      expect(find.byType(MgDialogFrame), findsOneWidget);
      await act();
      await tester.pumpAndSettle();
      return out;
    }

    expect(await run(() => tester.tap(find.text('Odejít'))), isTrue);
    expect(await run(() => tester.tap(find.text('Zůstat a počkat'))), isFalse);
    expect(await run(() => tester.tapAt(const Offset(5, 5))), isFalse);
  });

  testWidgets('payment methods: cards as cards; iOS view has no add action; delete asks in the v2 dialog', (tester) async {
    await pumpV2(
      tester,
      PaymentMethodsViewV2(
          cards: kPsCards, onBack: () {}, onRefresh: () async {}, onDelete: (_) {}, onSetDefault: (_) {}, onAdd: null, emptyNote: ''),
      scaffold: false,
    );
    expect(find.byKey(const ValueKey('pm-v2-add')), findsNothing);
    expect(find.text('Nastavit jako prioritní'), findsOneWidget, reason: 'only the non-priority card');

    final router = await pumpPs(tester, const PaymentMethodsScreen(), overrides: psShopOverrides());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PaymentMethodsViewV2), findsOneWidget);
    await tester.tap(find.text('Odebrat').first);
    await tester.pumpAndSettle();
    expect(find.byType(MgDialogFrame), findsOneWidget);
    await tester.tap(find.text('Zrušit'));
    await tester.pumpAndSettle();
    expect(find.byType(MgDialogFrame), findsNothing);
    expect(psPath(router), '/');
  });
}
