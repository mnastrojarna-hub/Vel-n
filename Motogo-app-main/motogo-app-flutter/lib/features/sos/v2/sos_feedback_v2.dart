import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/error_feedback.dart' show kMotoGoPhoneLabel;
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_sheet.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/widgets/mg_toast_rich.dart';

/// v2 SOS results (Stavy 14.3, 14.7–14.10). Same return ids as the old
/// dialogs ('call' / '112' / 'settings' / 'retry'; null = closed) — the
/// caller still decides what each one does.

/// 14.3 — an SOS action failed: SOS-tone T2, the red "Zavolat +420 …"
/// first, then 112, then "Zkusit znovu"; ✕ / swipe-down = close.
Future<String?> showSosFailSheetV2(BuildContext context, {required String title, required String body}) {
  final tr = t(context);
  return showMgSheet<String>(
    context,
    builder: (_) => MgStateSheetBody(tone: MgTone.sos, title: title, why: body, support: false),
    footer: Builder(
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgBtnSos(label: '${tr.tr('callLabel')} $kMotoGoPhoneLabel', onTap: () => Navigator.pop(ctx, 'call')),
        const SizedBox(height: 8),
        MgBtnDestructive(label: '112 · ${tr.tr('emergencyGeneral')}', filled: false, onTap: () => Navigator.pop(ctx, '112')),
        const SizedBox(height: 8),
        MgBtnGhostLight(label: tr.tr('eoRetry'), onTap: () => Navigator.pop(ctx, 'retry')),
      ]),
    ),
  );
}

/// 14.8–14.10 — the location did not arrive: warn T2 with the fix
/// ([settings] = "Otevřít nastavení"), the call and "Zkusit znovu".
Future<String?> showSosLocFailSheetV2(BuildContext context,
    {required String title, required String body, required bool settings}) {
  final tr = t(context);
  return showMgSheet<String>(
    context,
    builder: (_) => MgStateSheetBody(tone: MgTone.warn, icon: MgIcons.pin, title: title, why: body, support: false),
    footer: Builder(
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (settings) ...[
          MgBtnInk(label: tr.tr('eoOpenSettings'), icon: MgIcons.gear, onTap: () => Navigator.pop(ctx, 'settings')),
          const SizedBox(height: 8),
        ],
        MgBtnSos(label: '${tr.tr('callLabel')} $kMotoGoPhoneLabel', onTap: () => Navigator.pop(ctx, 'call')),
        const SizedBox(height: 8),
        MgBtnGhostLight(label: tr.tr('eoRetry'), onTap: () => Navigator.pop(ctx, 'retry')),
      ]),
    ),
  );
}

/// 14.7 — the location really arrived: one confirmation toast with the time.
void showSosLocSentV2(BuildContext context) {
  final tr = t(context);
  final n = DateTime.now();
  final time = '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
  showMgToastRich(context,
      title: tr.trArgs('v2UxAsmLocSent', {'time': time}),
      message: tr.tr('locationSharedMsg'),
      icon: MgIcons.pin);
}
