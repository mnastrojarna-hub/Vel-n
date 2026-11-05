import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_buttons.dart';
import '../widgets/mg_dialog.dart';

/// v2 (T6) looks of the EXISTING dialogs in `core/widgets/error_feedback.dart`
/// (V-seams inside their builders, PLAN §1.8). Same texts, same return
/// values — `Navigator.pop` results are identical to the old dialogs.

/// `showErrorDialog`: close (safe, returns null) + the caller's actions
/// (each returns its id).
Widget v2ErrorDialogLook(
  BuildContext ctx, {
  required String title,
  required String body,
  required List<(String id, String label)> actions,
  required bool showClose,
}) {
  final tr = t(ctx);
  final close = showClose
      ? MgBtnGhostLight(label: tr.tr('eoClose'), onTap: () => Navigator.pop(ctx))
      : null;
  if (actions.length <= 1) {
    final a = actions.isEmpty ? null : actions.first;
    return MgDialogFrame(
      title: title,
      body: body,
      safe: close,
      action: a == null ? null : MgBtnInk(label: a.$2, onTap: () => Navigator.pop(ctx, a.$1)),
      safeLabel: showClose ? tr.tr('eoClose') : null,
      actionLabel: a?.$2,
    );
  }
  return MgDialogFrame(
    title: title,
    body: body,
    extra: [
      for (final a in actions) MgBtnInk(label: a.$2, onTap: () => Navigator.pop(ctx, a.$1)),
      if (close != null) close,
    ],
  );
}

/// `confirmDiscard`: Zůstat (safe, false) · Zahodit (destructive, true).
Widget v2DiscardDialogLook(BuildContext ctx, {required String title, required String body}) {
  final tr = t(ctx);
  return MgDialogFrame(
    title: title,
    body: body,
    safe: MgBtnGhostLight(label: tr.tr('eoStay'), onTap: () => Navigator.pop(ctx, false)),
    action: MgBtnDestructive(label: tr.tr('eoDiscard'), onTap: () => Navigator.pop(ctx, true)),
    safeLabel: tr.tr('eoStay'),
    actionLabel: tr.tr('eoDiscard'),
  );
}

/// `MgProgress` dialog: spinner + live text; after the limit the slow hint
/// and "Zrušit" (the same cancel callback).
Widget v2ProgressDialogLook(
  BuildContext context, {
  required ValueNotifier<String> text,
  required bool slow,
  VoidCallback? onCancel,
}) {
  final tr = t(context);
  return MgDialogFrame(
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.6, color: MgColors.link),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: text,
            builder: (_, v, __) => Semantics(
              liveRegion: true,
              child: Text(v, style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink)),
            ),
          ),
        ),
      ]),
      if (slow) ...[
        const SizedBox(height: MgSpace.s12),
        Text(tr.tr('r3SlowHint'), style: MgType.small.copyWith(color: MgColors.body2)),
      ],
    ]),
    extra: [
      if (onCancel != null) Center(child: MgBtnText(label: tr.cancel, onTap: onCancel)),
    ],
  );
}
