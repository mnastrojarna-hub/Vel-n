import 'package:flutter/material.dart';

import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_dialog.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';

/// T6 look of a destructive confirm ("Smazat účet?", "Smazat doklad?"): Zrušit (safe, left) · Smazat
/// (destructive `#B42318`, right). [onDelete] = the caller's existing action, unchanged.
class DestructiveDialogV2 extends StatelessWidget {
  final String title;
  final String body;
  final String cancelLabel;
  final String deleteLabel;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  const DestructiveDialogV2({
    super.key,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.deleteLabel,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => MgDialogFrame(
        title: title,
        body: body,
        safe: MgBtnGhostLight(label: cancelLabel, onTap: onCancel),
        action: MgBtnDestructive(label: deleteLabel, onTap: onDelete),
        safeLabel: cancelLabel,
        actionLabel: deleteLabel,
      );
}

/// T6 look of the nickname dialog (V21 P3): text field + Resetovat ·
/// Zrušit · OK (stacked when a label does not fit). Same controller and
/// closures as `showNicknameDialog`.
class NicknameDialogV2 extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final String hint;
  final String resetLabel;
  final String cancelLabel;
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onOk;
  const NicknameDialogV2({
    super.key,
    required this.title,
    required this.controller,
    required this.hint,
    required this.resetLabel,
    required this.cancelLabel,
    required this.onReset,
    required this.onCancel,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) => MgDialogFrame(
        title: title,
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: MgColors.ink,
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(context, hint: hint),
        ),
        safe: MgBtnGhostLight(label: cancelLabel, onTap: onCancel),
        action: MgBtnInk(label: 'OK', neonLabel: true, onTap: onOk),
        safeLabel: cancelLabel,
        actionLabel: 'OK',
        extra: [Center(child: MgBtnText(label: resetLabel, onTap: onReset))],
      );
}
