import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'mg_word_fit.dart';

/// T5 toast — ONLY for non-blocking confirmations raised by v2 views
/// (Uloženo, Zkopírováno). Night glass r14, icon 20, 13.5/700, 2.8 s; with
/// an action 4 s. The text always takes the full width; the action (neon
/// text button, 44 high) sits under it at the end — never squeezing the text
/// (design D8). Errors that need action are never a toast (use the state
/// templates); snackbars from unchanged logic code are themed by
/// `MgThemeV2.overlay`. [lift] = extra bottom margin so the toast floats
/// above a page dock that sits in the body (it must not cover the dock's
/// buttons, e.g. ▶ Pokračovat right after ❚❚).
void showMgToast(
  BuildContext context,
  String message, {
  String icon = MgIcons.checkCircle,
  String? actionLabel,
  VoidCallback? onAction,
  double lift = 0,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(mgToastSnackBar(
      icon: icon,
      iconColor: MgColors.neon,
      title: message,
      actionLabel: actionLabel,
      onAction: onAction,
      messenger: messenger,
      lift: lift,
      duration: actionLabel != null ? MgMotion.toastAction : MgMotion.toast,
      titleMinScale: 0.85,
    ));
}

/// The v2 toast snackbar (shared by [showMgToast] and `showMgToastRich`).
SnackBar mgToastSnackBar({
  required String icon,
  required Color iconColor,
  required String title,
  String? message,
  String? actionLabel,
  VoidCallback? onAction,
  required ScaffoldMessengerState messenger,
  double lift = 0,
  required Duration duration,
  double titleMinScale = 1,
}) {
  final titleText = Text(title,
      style: MgType.small.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700, color: MgColors.onDark));
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: MgColors.night.withValues(alpha: 0.96),
    elevation: 0,
    margin: EdgeInsets.fromLTRB(16, 0, 16, 12 + lift),
    padding: EdgeInsets.fromLTRB(16, 12, 12, actionLabel == null ? 12 : 4),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: MgColors.neonA(0.25)),
    ),
    duration: duration,
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: message == null ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
        MgIcon(icon, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            titleMinScale < 1 ? MgWordFit(minScale: titleMinScale, child: titleText) : titleText,
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(message,
                  style: MgType.small.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: MgColors.onDarkLead)),
            ],
          ]),
        ),
      ]),
      if (actionLabel != null)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _ToastAction(
            label: actionLabel,
            onTap: () {
              messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
              onAction?.call();
            },
          ),
        ),
    ]),
  );
}

class _ToastAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ToastAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    textAlign: TextAlign.end,
                    style: MgType.small.copyWith(fontSize: 13.5, fontWeight: FontWeight.w800, color: MgColors.neon)),
              ),
            ),
          ),
        ),
      );
}
