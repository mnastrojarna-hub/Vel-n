import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/v2/flag/v2_scope.dart';
import '../v2/res_detail_bits_v2.dart';

/// Simple card container used in reservation detail sections.
class ResDetailCard extends StatelessWidget {
  final List<Widget> children;
  const ResDetailCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (MgV2.on(context)) return ResDetailCardV2(children: children);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}
