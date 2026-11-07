import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_toast_rich.dart';

/// "Platba se mezitím potvrdila" after a restart in the v2 look (T5 rich
/// toast): title, message, action and duration are read from the SAME
/// SnackBar the payment code builds (`paidAfterRestartSnackBar`), so no
/// text or action is decided here. false = unknown content shape → the
/// caller shows the original SnackBar.
bool showPaidToastV2(BuildContext context, SnackBar bar, {required bool failed}) {
  final c = bar.content;
  String? title, message;
  if (c is Text) {
    title = c.data;
  } else if (c is Column) {
    final texts = c.children.whereType<Text>().map((x) => x.data).whereType<String>().toList();
    if (texts.isNotEmpty) title = texts.first;
    if (texts.length > 1) message = texts[1];
  }
  final action = bar.action;
  if (title == null || action == null) return false;
  showMgToastRich(
    context,
    title: title,
    message: message,
    tone: failed ? MgTone.warn : MgTone.ok,
    icon: failed ? MgIcons.warn : MgIcons.checkCircle,
    actionLabel: action.label,
    onAction: action.onPressed,
    duration: bar.duration,
  );
  return true;
}
