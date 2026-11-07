import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// v2 look of `SosHereAddress` ("Kde právě jsi"): a light row on the SOS
/// page — gps / ✓ icon (spinner while locating), title 15/800 and the
/// state line (locating / used / the found address / "klepni"). The tap is
/// the widget's own `_tap` (use the found address, or locate first).
class SosHereAddressV2 extends StatelessWidget {
  final String title;
  final String sub;
  final bool busy;
  final bool used;
  final VoidCallback onTap;
  const SosHereAddressV2({
    super.key,
    required this.title,
    required this.sub,
    required this.busy,
    required this.used,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title. $sub',
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: used ? MgColors.tintOk : MgColors.surface,
              borderRadius: BorderRadius.circular(MgRadius.button),
              border: Border.all(color: used ? MgColors.tintOkBorder : MgColors.line, width: used ? 1.5 : 1),
            ),
            child: Row(children: [
              SizedBox(
                width: 22,
                height: 22,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link),
                      )
                    : MgIcon(used ? MgIcons.checkCircle : MgIcons.gps, size: 22, color: used ? MgColors.onTintOk : MgColors.link),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: MgType.title.copyWith(color: used ? MgColors.onTintOk : MgColors.ink)),
                  const SizedBox(height: 2),
                  Text(sub, style: MgType.small.copyWith(color: MgColors.meta)),
                ]),
              ),
              const SizedBox(width: 8),
              const MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.meta),
            ]),
          ),
        ),
      );
}
