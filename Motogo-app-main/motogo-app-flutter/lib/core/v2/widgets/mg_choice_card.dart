import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';

/// One option of a single choice shown as a card (SOS cause, payment
/// method, voucher variant…): white r16 1 px line, min height 64; selected
/// = ok tint + 1.5 px `#37CF63` + a 24 px ✓ disc that pops in. Radio
/// semantics; [onTap] = the caller's existing selection action.
class MgChoiceCard extends StatelessWidget {
  final String title;
  final String? sub;
  final String? icon;
  final bool selected;
  final VoidCallback? onTap;
  const MgChoiceCard({
    super.key,
    required this.title,
    this.sub,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.color);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      selected: selected,
      button: true,
      enabled: onTap != null,
      label: sub == null ? title : '$title, $sub',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: d,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MgColors.tintOk : MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? MgColors.tintOkBorder : MgColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            if (icon != null) ...[
              MgIcon(icon!, size: 22, color: selected ? MgColors.onTintOk : MgColors.link),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: selected ? MgColors.onTintOk : MgColors.ink)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: MgType.small.copyWith(color: MgColors.meta)),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 24,
              height: 24,
              child: selected
                  ? MgPop(
                      playOnMount: true,
                      child: Container(
                        key: const ValueKey('mg-choice-check'),
                        decoration: const BoxDecoration(color: MgColors.link, shape: BoxShape.circle),
                        child: const Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.onDark, stroke: 2.6)),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: MgColors.lineInput, width: 1.5),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
