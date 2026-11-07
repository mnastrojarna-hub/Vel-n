import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../../core/v2/flag/v2_scope.dart';
import '../v2/res_cancel_v2.dart';
import '../reservation_provider.dart' show CancelResult;

/// Obsah dialogu storna PO odeslání (2026-10-16): potvrzení s vratkou, nebo
/// srozumitelná chyba s nápravou. Dřív se odmítnutí serverem (`{error}`)
/// tvářilo jako úspěch a výjimka se ukázala syrově („Chyba storna:
/// PostgrestException…") — česky ve všech jazycích.
Widget cancelResultDialog(
  BuildContext context,
  CancelResult r, {
  required bool wasPaid,
  required VoidCallback onClose,
  required VoidCallback onRetry,
}) {
  final tr = t(context);
  // „Už je zrušená" (typicky opakování po ztracené odpovědi — storno prošlo
  // napoprvé) je výsledek, ne chyba → potvrzení, ne „nepodařilo se".
  if (r.ok || r.error == 'already') {
    final body = r.error == 'already'
        ? tr.tr('psCancelAlready')
        : !wasPaid
        ? tr.tr('psCancelUnpaid')
        : !r.refundKnown
        ? tr.tr('fxCancelDoneRefundLater')
        : r.refundAmount > 0
            ? tr
                .tr('psCancelRefund')
                .replaceAll('{amount}', Money.czk(r.refundAmount))
                .replaceAll('{pct}', '${r.refundPercent}')
            : tr.tr('psCancelNoRefund');
    // v2 vzhled (kill-switch app_v2_ui): stejný text i tlačítko.
    if (MgV2.on(context)) {
      return ResCancelResultV2(
          ok: true, title: tr.tr('psCancelDoneTitle'), body: body, closeLabel: tr.tr('close'), onClose: onClose);
    }
    return AlertDialog(
      title: Text('✓ ${tr.tr('psCancelDoneTitle')}',
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body),
      actions: [
        ElevatedButton(onPressed: onClose, child: Text(tr.tr('close'))),
      ],
    );
  }
  final key = switch (r.error) {
    'already' => 'psCancelAlready',
    'forbidden' => 'pdCancelForbidden',
    'not_found' => 'psCancelNotFound',
    'network' => 'psCancelNet',
    'uncertain' => 'fxCancelUncertain',
    _ => 'pdCancelFail',
  };
  final canRetry =
      r.error == 'network' || r.error == 'failed' || r.error == 'uncertain';
  if (MgV2.on(context)) {
    return ResCancelResultV2(
      ok: false,
      title: tr.tr(r.error == 'uncertain' ? 'psUncertainTitle' : 'psCancelFailTitle'),
      body: tr.tr(key),
      closeLabel: canRetry ? tr.back : tr.tr('close'),
      onClose: onClose,
      onRetry: canRetry ? onRetry : null,
    );
  }
  return AlertDialog(
    title: Text(tr.tr(r.error == 'uncertain' ? 'psUncertainTitle' : 'psCancelFailTitle'),
        style: const TextStyle(fontWeight: FontWeight.w800, color: MotoGoColors.red)),
    content: Text(tr.tr(key)),
    actions: [
      TextButton(onPressed: onClose, child: Text(canRetry ? tr.back : tr.tr('close'))),
      if (canRetry)
        ElevatedButton(onPressed: onRetry, child: Text(tr.tr('retry'))),
    ],
  );
}
