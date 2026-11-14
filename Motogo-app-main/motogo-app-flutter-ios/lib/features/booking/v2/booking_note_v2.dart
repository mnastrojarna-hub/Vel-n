import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_inputs.dart';

/// "Poznámka k rezervaci" (old `_buildNoteSection`): collapsible card, the
/// form's OWN controller, toggle and onChanged (max 500 chars, 3 lines).
class BookingNoteCardV2 extends StatelessWidget {
  final TextEditingController controller;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  const BookingNoteCardV2({
    super.key,
    required this.controller,
    required this.open,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final hasNote = controller.text.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.card),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: open,
          label: tr.tr('bookingNoteToggle') + (!open && hasNote ? ', ${tr.tr('v2BkNoteSaved')}' : ''),
          excludeSemantics: true,
          onTap: onToggle,
          child: MgPress(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(MgSpace.card),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MgColors.well,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MgColors.line),
                  ),
                  child: Center(child: MgIcon(MgIcons.edit, size: 18, color: MgColors.link)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr.tr('bookingNoteToggle'),
                      style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink, height: 1.3)),
                ),
                if (!open && hasNote) ...[
                  MgIcon(MgIcons.checkCircle, size: 18, color: MgColors.link),
                  const SizedBox(width: 6),
                ],
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: MgMotion.of(context, MgMotion.color),
                  child: MgIcon(MgIcons.chevronDown, size: 20, color: MgColors.meta),
                ),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: MgEnter(
              child: TextField(
                controller: controller,
                maxLines: 3,
                maxLength: 500,
                style: MgType.body.copyWith(color: MgColors.ink),
                decoration: mgInputDecoration(context, hint: tr.tr('v2BkNoteHint')),
                onChanged: onChanged,
              ),
            ),
          ),
      ]),
    );
  }
}
