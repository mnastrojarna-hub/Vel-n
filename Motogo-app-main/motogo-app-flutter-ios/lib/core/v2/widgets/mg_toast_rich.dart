import 'package:flutter/material.dart';

import '../chrome/mg_chrome_metrics.dart';
import '../motion/mg_motion.dart';
import '../states/mg_tone.dart';
import '../tokens/mg_colors.dart';
import 'mg_toast.dart';

/// T5 toast with a title + message line and a meaning tone (design D8): the
/// v2 look of the old `showMotoGoToast` / `showErrorSnack` calls. Night
/// glass r14, 1 px neon .25; icon by tone (ok neon, warn / pending
/// `#FFD36B`, err `#FFB3B3`, info / SOS white); title 13.5/700 white,
/// message 12.5/600 `#CFE7DA`; the action under the text (neon, 44 high).
/// [lift] defaults to the current page dock, so it never covers a dock.
void showMgToastRich(
  BuildContext context, {
  required String title,
  String? message,
  MgTone tone = MgTone.ok,
  String? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  double? lift,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final style = mgToneStyle(tone, dark: true);
  final color = switch (tone) {
    MgTone.ok => MgColors.neon,
    MgTone.warn || MgTone.pending => MgColors.warnDark,
    MgTone.err => MgColors.errDark,
    MgTone.info || MgTone.sos => MgColors.onDark,
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(mgToastSnackBar(
      icon: icon ?? style.iconName,
      iconColor: color,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      messenger: messenger,
      lift: lift ?? MgChromeScope.chromeOf(context)?.dockHeight ?? 0,
      duration: duration ?? (actionLabel != null ? MgMotion.toastAction : MgMotion.toast),
    ));
}
