import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';

/// An action of a state template (label + the caller's EXISTING callback).
class MgStateAction {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool destructive;
  final bool sos;
  final String? icon;
  const MgStateAction(
    this.label,
    this.onTap, {
    this.busy = false,
    this.destructive = false,
    this.sos = false,
    this.icon,
  });
}

/// "Co bude dál" / "Jak to vyřešit" numbered steps: 34 px dark discs with
/// neon numbers (compact = 20 px numbers for sheets).
class MgStateSteps extends StatelessWidget {
  final String? title;
  final List<String> steps;
  final bool dark;
  final bool compact;
  const MgStateSteps({super.key, this.title, required this.steps, this.dark = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final disc = compact ? 22.0 : 34.0;
    final textStyle = (compact ? MgType.small : MgType.body)
        .copyWith(color: dark ? MgColors.onDarkBody : MgColors.body2);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (title != null) ...[
        Semantics(
          header: true,
          child: Text(title!, style: MgType.title.copyWith(color: dark ? MgColors.onDark : MgColors.ink)),
        ),
        const SizedBox(height: 10),
      ],
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 10),
          child: MergeSemantics(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  color: dark ? MgColors.white(0.08) : MgColors.panel,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('${i + 1}',
                      style: MgType.tab(MgType.title.copyWith(
                          fontSize: compact ? 12 : 15, fontWeight: FontWeight.w900, color: MgColors.neon))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: compact ? 2 : 7),
                  child: Text(steps[i], style: textStyle),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}
