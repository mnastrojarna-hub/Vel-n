import 'package:flutter/material.dart';

import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// v2 look of `ResDetailCard` (white card, 1 px line, r16) — used by the
/// leaf widgets that still build their own cards (history, codes in v1…).
class ResDetailCardV2 extends StatelessWidget {
  final List<Widget> children;
  const ResDetailCardV2({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.line),
          boxShadow: MgShadows.card,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// v2 look of `ResDetailRow` (label lead, value ink; same value colour
/// override, mapped to the v2 meaning colours).
class ResDetailRowV2 extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final bool bold;
  final Color? valueColor;
  const ResDetailRowV2({super.key, required this.label, this.value, this.child, this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: MgType.small.copyWith(color: MgColors.lead))),
          const SizedBox(width: 12),
          child ??
              Flexible(
                child: Text(value ?? '',
                    textAlign: TextAlign.right,
                    style: MgType.tab(MgType.small.copyWith(
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w700, color: valueColor ?? MgColors.ink))),
              ),
        ]),
      );
}
