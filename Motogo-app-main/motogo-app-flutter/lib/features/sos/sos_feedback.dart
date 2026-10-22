import 'package:flutter/material.dart';

import '../../core/friendly_error.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/error_feedback.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_location.dart';

/// Hlášky SOS (2026-10-16): v nouzi NIKDY falešný úspěch ani slepá ulička —
/// vždy důvod + volání na nonstop linku / 112 (hovor jde i bez dat).

/// Neblokovatelný průběh odesílání („Odesílám hlášení… (zjišťuji polohu)").
typedef SosProgress = MgProgress;

/// SOS akce se nepovedla (hlášení, odtah, náhrada, „jedu dál").
/// [title] = co se nepovedlo. Vrací true, když zákazník zvolil Zkusit znovu.
Future<bool> showSosActionFailed(
  BuildContext context, {
  required String title,
  required Object? error,
  String? extra,
}) async {
  FriendlyError.log('sos_action_failed', error);
  final tr = t(context);
  final fe = FriendlyError.of(error);
  final why = '${fe.reason(tr)[0].toUpperCase()}${fe.reason(tr).substring(1)}.';
  final body = [why, if (extra != null) extra, tr.tr('eoSosCallUs')].join(' ');
  final r = await showErrorDialog(context,
      title: title,
      body: body,
      actions: [
        ('call', '📞 ${tr.tr('eoCallNonstop')}'),
        ('112', '🆘 112'),
        ('retry', tr.tr('eoRetry')),
      ]);
  if (r == 'call') await callMotoGo();
  if (r == '112') await call112();
  return r == 'retry';
}

/// Výsledek „Sdílet polohu": úspěch jen při [SosLocResult.ok], jinak důvod +
/// Zavolat / Otevřít nastavení / Zkusit znovu. Vrací true = zkusit znovu.
Future<bool> showSosLocationResult(BuildContext context, SosLocResult r) async {
  final tr = t(context);
  if (r == SosLocResult.ok) {
    showMotoGoToast(context,
        icon: '📍', title: tr.tr('locationShared'), message: tr.tr('locationSharedMsg'));
    return false;
  }
  final reason = switch (r) {
    SosLocResult.noPermission => tr.tr('eoPermReasonLocation'),
    SosLocResult.serviceOff => tr.tr('eoLocOffReason'),
    SosLocResult.noFix => tr.tr('eoSosNoFixReason'),
    SosLocResult.offline => tr.tr('eoOfflineReason'),
    _ => tr.tr('eoUnknownReason'),
  };
  final settings = r == SosLocResult.noPermission || r == SosLocResult.serviceOff;
  final choice = await showErrorDialog(context,
      title: tr.tr('eoSosLocFailTitle'),
      body: tr.trArgs('eoSosLocFailBody', {'reason': reason}),
      actions: [
        ('call', '📞 ${tr.tr('eoCallNonstop')}'),
        if (settings) ('settings', tr.tr('eoOpenSettings')),
        ('retry', tr.tr('eoRetry')),
      ]);
  if (choice == 'call') await callMotoGo();
  if (choice == 'settings') {
    await openFixSettings(FriendlyError(
        r == SosLocResult.serviceOff ? FriendlyKind.locationOff : FriendlyKind.permission));
  }
  return choice == 'retry';
}

/// Hlášení odešlo, ale bez polohy → zákazník musí říct dispečerovi, kde je.
void showSosSentWithoutLocation(BuildContext context) {
  final tr = t(context);
  showMotoGoToast(context,
      icon: '📍',
      title: tr.tr('eoSosNoLocTitle'),
      message: tr.tr('eoSosNoLocBody'),
      duration: const Duration(seconds: 9));
}

/// Červené tlačítko „Zavolat nonstop linku" pro chybové stavy SOS obrazovek.
class SosCallButton extends StatelessWidget {
  const SosCallButton({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: callMotoGo,
      style: OutlinedButton.styleFrom(
          foregroundColor: MotoGoColors.red,
          side: const BorderSide(color: MotoGoColors.red)),
      child: Text('📞 ${t(context).tr('eoCallNonstop')}'),
    );
  }
}
