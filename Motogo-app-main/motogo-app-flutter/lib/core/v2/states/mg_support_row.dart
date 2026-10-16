import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../../widgets/error_feedback.dart' show callMotoGo, kMotoGoPhoneLabel;
import '../chrome/mg_nav_helpers.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';

/// "Pomůžeme ti:" + Zavolat (+420 774 256 271, existing `callMotoGo`) +
/// Napsat nám (Zprávy). [onWrite] overrides the default `/messages` push
/// (e.g. outside a router or with a prefilled thread).
class MgSupportRow extends StatelessWidget {
  final bool dark;
  final VoidCallback? onWrite;
  final bool showWrite;
  const MgSupportRow({super.key, this.dark = false, this.onWrite, this.showWrite = true});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lead = dark ? MgColors.onDarkLead : MgColors.lead;
    final link = dark ? MgColors.neonText : MgColors.link;
    Widget action(String icon, String label, String? sub, VoidCallback onTap) => Semantics(
          button: true,
          label: sub == null ? label : '$label $sub',
          excludeSemantics: true,
          onTap: onTap,
          child: MgPress(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MgIcon(icon, size: 18, color: link),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: link)),
                      if (sub != null)
                        TextSpan(text: ' $sub', style: MgType.tab(MgType.small.copyWith(color: lead))),
                    ])),
                  ),
                ]),
              ),
            ),
          ),
        );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 0,
      children: [
        Text(tr.tr('v2StHelp'), style: MgType.small.copyWith(color: lead)),
        action(MgIcons.phone, tr.tr('v2StCall'), kMotoGoPhoneLabel, () => callMotoGo()),
        if (showWrite)
          action(MgIcons.chat, tr.tr('v2StWrite'), null,
              onWrite ?? () => mgPushOrGo(context, kV2MessagesRoute)),
      ],
    );
  }
}
