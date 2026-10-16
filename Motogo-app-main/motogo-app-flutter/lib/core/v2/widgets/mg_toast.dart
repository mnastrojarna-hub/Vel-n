import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'mg_word_fit.dart';

/// T5 toast — ONLY for non-blocking confirmations raised by v2 views
/// (Uloženo, Zkopírováno). Night glass r14, icon 20, 13.5/700, 2.8 s; with
/// an action 4 s. Errors that need action are never a toast (use the state
/// templates); snackbars from unchanged logic code are themed by
/// `MgThemeV2.overlay`.
void showMgToast(
  BuildContext context,
  String message, {
  String icon = MgIcons.checkCircle,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MgColors.night.withValues(alpha: 0.96),
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: MgColors.neonA(0.25)),
      ),
      duration: actionLabel != null ? MgMotion.toastAction : MgMotion.toast,
      content: Row(children: [
        MgIcon(icon, size: 20, color: MgColors.neon),
        const SizedBox(width: 10),
        Expanded(
          child: MgWordFit(
            minScale: 0.85,
            child: Text(message,
                style: MgType.small.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700, color: MgColors.onDark)),
          ),
        ),
      ]),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, textColor: MgColors.neon, onPressed: onAction ?? () {}),
    ));
}
