import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// The program rules (same keys as the old LoyaltyRankCard sheet) in a
/// light v2 sheet.
void showClubRulesSheet(BuildContext context) {
  final tr = t(context);
  final rules = [
    tr.tr('loyaltyRulePoints'),
    tr.tr('loyaltyRuleLong'),
    tr.tr('loyaltyRuleLevel'),
    tr.tr('loyaltyRuleAppOnly'),
    tr.tr('loyaltyRuleCombo'),
  ];
  showMgSheet<void>(
    context,
    title: tr.tr('loyaltyInfoTitle'),
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final r in rules)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: MgIcon(MgIcons.checkCircle, size: 18, color: MgColors.link),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(r, style: MgType.body.copyWith(color: MgColors.body2))),
          ]),
        ),
    ]),
  );
}
