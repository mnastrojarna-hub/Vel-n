// pay_shop PS-03 / 04 / 21: thank-you page and payment result in the v2
// look — tones per outcome, the same destinations, pending → success on
// the same screen, the verify action, exactly one CTA loop, reduced
// motion static.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_anim_loops.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/payment/payment_result_screen.dart';
import 'package:motogo_app/features/payment/v2/confirmation_view_v2.dart';
import 'package:motogo_app/features/payment/v2/result_view_v2.dart';

import '../render/cases_ux_pay_shop.dart' show psConfirm, psOutcome;
import '../support/ps_harness.dart';
import '../support/v2_harness.dart' show pumpV2;

MgTone _tone(WidgetTester t) => t.widget<MgStateScreen>(find.byType(MgStateScreen)).tone;

void main() {
  testWidgets('every outcome renders its tone; ✕ and the CTA go where the old ones went', (tester) async {
    final tones = {
      PaymentOutcomeKind.success: MgTone.ok,
      PaymentOutcomeKind.pending: MgTone.pending,
      PaymentOutcomeKind.attention: MgTone.warn,
      PaymentOutcomeKind.failed: MgTone.err,
    };
    for (final k in PaymentOutcomeKind.values) {
      final router = await pumpPs(tester, const PaymentResultScreen(),
          overrides: [paymentOutcomeProvider.overrideWith((ref) => psOutcome(k))]);
      expect(find.byType(ResultViewV2), findsOneWidget, reason: k.name);
      expect(_tone(tester), tones[k], reason: k.name);
      expect(find.byKey(const ValueKey('pay-result-verify')), k == PaymentOutcomeKind.pending ? findsOneWidget : findsNothing);
      await tester.tap(find.bySemanticsLabel('Zavřít').first);
      await tester.pumpAndSettle();
      expect(psPath(router), '/reservations', reason: '${k.name} ✕');
    }
    final router = await pumpPs(tester, const PaymentResultScreen(),
        overrides: [paymentOutcomeProvider.overrideWith((ref) => psOutcome(PaymentOutcomeKind.success))]);
    await tester.tap(find.text('MOJE REZERVACE'));
    await tester.pumpAndSettle();
    expect(psPath(router), '/reservations');
  });

  testWidgets('pending switches itself to success on the same screen (same widget, ok tone)', (tester) async {
    await pumpPs(tester, const PaymentResultScreen(),
        overrides: [paymentOutcomeProvider.overrideWith((ref) => psOutcome(PaymentOutcomeKind.pending))]);
    expect(_tone(tester), MgTone.pending);
    final el = tester.element(find.byType(MgStateScreen));
    ProviderScope.containerOf(el).read(paymentOutcomeProvider.notifier).state = psOutcome(PaymentOutcomeKind.success);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_tone(tester), MgTone.ok);
    expect(tester.element(find.byType(MgStateScreen)), same(el));
  });

  testWidgets('thank-you: buttons keep their destinations; documents missing → upload first', (tester) async {
    var closed = 0, docs = 0;
    Widget view(PayDocsV2 d) => ConfirmationViewV2(
          restored: false, shortId: '#8F3A2C1D', motoName: 'BMW', start: DateTime(2026, 10, 23), end: DateTime(2026, 10, 25),
          pickup: null, branchName: null, pickupTime: '12:00', returnTime: null, lateGateDate: null, docs: d,
          missingReason: null, noDetails: false, loadFailed: false, paidTotal: null,
          onRetry: () {}, onClose: () => closed++, onDocs: () => docs++);
    await pumpV2(tester, view(PayDocsV2.verified), scaffold: false);
    await tester.tap(find.text('MOJE REZERVACE'));
    expect(closed, 1);
    await tester.tap(find.bySemanticsLabel('Zavřít').first);
    expect(closed, 2);
    await pumpV2(tester, view(PayDocsV2.missing), scaffold: false);
    await tester.tap(find.text('NAHRÁT DOKLADY TEĎ'));
    expect(docs, 1);
    await tester.tap(find.text('Moje rezervace'));
    expect(closed, 3);
  });

  testWidgets('thank-you: one CTA loop at most; reduced motion = no loop, static', (tester) async {
    await pumpV2(tester, psConfirm(), scaffold: false);
    final loops = tester.widgetList<MgLoopClock>(find.byType(MgLoopClock)).where((l) => l.active).length;
    expect(loops, 1);
    await pumpV2(tester, psConfirm(), scaffold: false, reducedMotion: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('thank-you: number, dates, "Zaplaceno" from the form, safety tips OPEN (old look), foldable', (tester) async {
    await pumpV2(tester, psConfirm(), scaffold: false, reducedMotion: true);
    expect(find.textContaining('#8F3A2C1D'), findsOneWidget);
    expect(find.text('ZAPLACENO'), findsOneWidget);
    // Always visible at first, incl. the liability line (owner "nic neomezit").
    expect(find.textContaining('Nikdy nenechávej', skipOffstage: false), findsOneWidget);
    await tester.ensureVisible(find.text('Bezpečnostní pokyny'));
    await tester.tap(find.text('Bezpečnostní pokyny'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nikdy nenechávej'), findsNothing);
  });

  testWidgets('thank-you: load failure = info + "Zkusit znovu" (the screen\'s retry)', (tester) async {
    var retried = 0;
    await pumpV2(
        tester,
        ConfirmationViewV2(
            restored: true, shortId: null, motoName: null, start: null, end: null, pickup: null, branchName: null,
            pickupTime: null, returnTime: null, lateGateDate: null, docs: PayDocsV2.unknown, missingReason: null,
            noDetails: true, loadFailed: true, paidTotal: null, onRetry: () => retried++, onClose: () {}, onDocs: () {}),
        scaffold: false);
    expect(find.text('Rezervace je znovu potvrzená'), findsOneWidget);
    await tester.tap(find.text('Zkusit znovu'));
    expect(retried, 1);
  });
}
