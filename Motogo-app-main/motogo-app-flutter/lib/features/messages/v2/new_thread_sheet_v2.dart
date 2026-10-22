import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 look of the "Nová konverzace" sheet (V21 S3): light sheet, subject
/// input, pinned "Odeslat". Validation + create live in the screen
/// ([onSubmitted] = keyboard enter, [onSend] = button — today's closures).
class NewThreadSheetV2View extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onSend;
  final VoidCallback onClose;
  const NewThreadSheetV2View({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgSheetFrame(
      title: tr.tr('newConversation'),
      onClose: onClose,
      footer: MgBtnInk(label: tr.tr('send'), icon: MgIcons.send, neonLabel: true, onTap: onSend),
      child: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        style: MgType.body.copyWith(color: MgColors.ink),
        decoration: mgInputDecoration(context, hint: tr.tr('conversationTopic')),
        onSubmitted: onSubmitted,
      ),
    );
  }
}
