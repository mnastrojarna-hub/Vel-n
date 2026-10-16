import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../reservation_provider.dart' show CancelResult;

/// Obsah dialogu storna PO odeslání (2026-10-16): potvrzení s vratkou, nebo
/// srozumitelná chyba s nápravou. Dřív se odmítnutí serverem (`{error}`)
/// tvářilo jako úspěch a výjimka se ukázala syrově („Chyba storna:
/// PostgrestException…") — česky ve všech jazycích.
AlertDialog cancelResultDialog(
  BuildContext context,
  CancelResult r, {
  required bool wasPaid,
  required VoidCallback onClose,
  required VoidCallback onRetry,
}) {
  final tr = t(context);
  if (r.ok) {
    final body = !wasPaid
        ? tr.tr('psCancelUnpaid')
        : r.refundAmount > 0
            ? tr
                .tr('psCancelRefund')
                .replaceAll('{amount}', Money.czk(r.refundAmount))
                .replaceAll('{pct}', '${r.refundPercent}')
            : tr.tr('psCancelNoRefund');
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
    'forbidden' => 'psCancelForbidden',
    'not_found' => 'psCancelNotFound',
    'network' => 'psCancelNet',
    _ => 'psCancelFail',
  };
  final canRetry = r.error == 'network' || r.error == 'failed';
  return AlertDialog(
    title: Text(tr.tr('psCancelFailTitle'),
        style: const TextStyle(fontWeight: FontWeight.w800, color: MotoGoColors.red)),
    content: Text(tr.tr(key)),
    actions: [
      TextButton(onPressed: onClose, child: Text(canRetry ? tr.back : tr.tr('close'))),
      if (canRetry)
        ElevatedButton(onPressed: onRetry, child: Text(tr.tr('retry'))),
    ],
  );
}
