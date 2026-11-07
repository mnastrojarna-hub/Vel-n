// FND-7: toast layout (text full width, action under it), rich toast,
// emoji → line icon bridge, v2 error toast, emoji stripping.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/friendly_error.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/core/v2/widgets/mg_emoji_map.dart';
import 'package:motogo_app/core/v2/widgets/mg_toast.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';
import 'package:motogo_app/features/auth/widgets/toast_helper.dart';

import '../support/v2_harness.dart';

Future<void> _pump(WidgetTester tester, void Function(BuildContext) open, {bool v2 = true}) async {
  await loadMontserrat();
  await pumpV2(
    tester,
    Builder(builder: (c) => Center(child: TextButton(onPressed: () => open(c), child: const Text('open')))),
    v2: v2,
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('60-char message + action: text takes the width, action under it', (tester) async {
    var taps = 0;
    const msg = 'Rezervace je uložená, potvrzení ti přijde e-mailem za chvíli.';
    expect(msg.length, greaterThanOrEqualTo(60));
    await _pump(tester, (c) => showMgToast(c, msg, actionLabel: 'Zpět', onAction: () => taps++));
    final bar = tester.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
    final text = tester.getRect(find.text(msg));
    expect(text.width, greaterThanOrEqualTo(0.8 * bar.width));
    expect(bar.height, lessThanOrEqualTo(140));
    final action = tester.getRect(find.text('Zpět'));
    expect(action.top, greaterThan(text.bottom - 1));
    expect(find.byType(SnackBarAction), findsNothing);
    await tester.tap(find.text('Zpět'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text(msg), findsNothing);
  });

  testWidgets('flag ON: showMotoGoToast(✓) → line icon, no emoji text', (tester) async {
    await _pump(tester, (c) => showMotoGoToast(c, icon: '✓', title: 'Uloženo', message: 'Profil je aktuální 👍'));
    expect(find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.checkCircle), findsOneWidget);
    expect(find.text('✓'), findsNothing);
    expect(find.text('Uloženo'), findsOneWidget);
    expect(find.text('Profil je aktuální'), findsOneWidget);
  });

  testWidgets('flag OFF: showMotoGoToast keeps the old emoji toast', (tester) async {
    await _pump(tester, v2: false, (c) => showMotoGoToast(c, icon: '✓', title: 'Uloženo'));
    expect(find.text('✓'), findsOneWidget);
    expect(find.byType(MgIcon), findsNothing);
  });

  testWidgets('v2 error toast: offline text is gender-neutral, retry action works', (tester) async {
    var retried = 0;
    await _pump(tester, (c) => showErrorSnack(c, 'Uložení se nepodařilo', null,
        friendly: const FriendlyError(FriendlyKind.offline), onRetry: () => retried++));
    expect(find.text('Uložení se nepodařilo'), findsOneWidget);
    expect(find.text('Telefon je offline. Zapni data nebo Wi-Fi a zkus to znovu.'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.wifiOff), findsOneWidget);
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(retried, 1);
  });

  test('emoji map and stripping', () {
    expect(mgToastLookFor('✅'), (MgIcons.checkCircle, MgTone.ok));
    expect(mgToastLookFor('⚠️'), (MgIcons.warn, MgTone.warn));
    expect(mgToastLookFor('❌'), (MgIcons.xCircle, MgTone.err));
    expect(mgToastLookFor('⏳'), (MgIcons.clock, MgTone.pending));
    expect(mgToastLookFor('🛰️'), (MgIcons.satellite, MgTone.info));
    expect(mgToastLookFor(null), (MgIcons.info, MgTone.info));
    expect(mgStripEmoji('Záznam jízdy běží 🛰️'), 'Záznam jízdy běží');
    expect(mgStripEmoji('✓ Uloženo ✓.'), 'Uloženo.');
    expect(mgStripEmoji('Ahoj 👋🏽 Petro'), 'Ahoj Petro');
    expect(mgStripEmoji('Rodina 👨‍👩‍👧 jede'), 'Rodina jede');
    expect(mgStripEmoji('pá 23. 10. → ne 25. 10. · © OSM'), 'pá 23. 10. → ne 25. 10. · © OSM');
    expect(mgStripEmoji('🇨🇿 Česko'), 'Česko');
  });
}
