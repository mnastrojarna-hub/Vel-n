import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// The 5 rules of today's "O programu" sheet (`LoyaltyRankCard`), same keys
/// and order.
const List<String> kLoyaltyInfoRuleKeys = [
  'loyaltyRulePoints',
  'loyaltyRuleLong',
  'loyaltyRuleLevel',
  'loyaltyRuleAppOnly',
  'loyaltyRuleCombo',
];

/// v2 look of the "O programu" sheet (light sheet, line ✓ icons). Strings
/// are resolved up-front against the caller's context (as today).
Future<void> showLoyaltyInfoSheetV2(BuildContext context) {
  final tr = t(context);
  final title = tr.tr('loyaltyInfoTitle');
  final rules = [for (final k in kLoyaltyInfoRuleKeys) tr.tr(k)];
  return showMgSheet<void>(
    context,
    title: title,
    builder: (_) => LoyaltyRulesList(rules: rules),
  );
}

/// ✓ list of rules (light surfaces).
class LoyaltyRulesList extends StatelessWidget {
  final List<String> rules;
  const LoyaltyRulesList({super.key, required this.rules});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const MgIcon(MgIcons.check, size: 20, color: MgColors.link, stroke: 2.5),
                const SizedBox(width: 8),
                Expanded(child: Text(r, style: MgType.small.copyWith(color: MgColors.body2, height: 1.45))),
              ]),
            ),
        ],
      );
}
