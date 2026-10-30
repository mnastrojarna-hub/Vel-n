import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../submit_common.dart';

/// v2 look of the planner's "Uložit trasu" / "Navrhnout do komunity"
/// sheets: light sheet with the 44 px ✕, the hint (or the moderation
/// note), name + description prefilled from `RouteNameMemory` and the
/// pinned ink button. Validation, sending and the memory stay in
/// `route_builder_sheets.dart` ([onSend] = today's handler).
class RouteNameSheetV2 extends StatelessWidget {
  final String title;

  /// Hint under the title (save); null = the moderation note (suggest).
  final String? hintKey;
  final TextEditingController name;
  final String nameLabel;
  final TextEditingController desc;
  final String descLabel;
  final int descLines;
  final String sendLabel;
  final bool busy;
  final VoidCallback onSend;
  const RouteNameSheetV2({
    super.key,
    required this.title,
    required this.hintKey,
    required this.name,
    required this.nameLabel,
    required this.desc,
    required this.descLabel,
    required this.descLines,
    required this.sendLabel,
    required this.busy,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final style = MgType.body.copyWith(color: MgColors.ink);
    return MgSheetFrame(
      title: title,
      footer: MgBtnInk(label: sendLabel, busy: busy, onTap: busy ? null : onSend),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hintKey != null)
          Text(t(context).tr(hintKey!), style: MgType.body.copyWith(color: MgColors.body2))
        else
          const SubmitIntroBanner(),
        const SizedBox(height: 16),
        TextField(controller: name, style: style, decoration: mgInputDecoration(context, label: nameLabel)),
        const SizedBox(height: 12),
        TextField(
          controller: desc,
          maxLines: descLines,
          style: style,
          decoration: mgInputDecoration(context, label: descLabel),
        ),
      ]),
    );
  }
}
