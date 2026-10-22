import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../motion/mg_anim_loops.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';

/// Loading placeholder block. Shimmers (1.2 s) only while [loading];
/// reduced motion → static at 55 %. Never use it for content that failed —
/// show an error state instead.
class MgSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool dark;
  final bool loading;
  const MgSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.dark = false,
    this.loading = true,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MgShimmer(
        active: loading,
        highlight: dark ? const Color(0x22FFFFFF) : const Color(0x99FFFFFF),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: dark ? MgColors.white(0.08) : const Color(0xFFE6EDE9),
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}

/// A card-shaped skeleton (image band + 2 text lines) for lists.
class MgSkeletonCard extends StatelessWidget {
  final double imageHeight;
  final bool dark;
  const MgSkeletonCard({super.key, this.imageHeight = 120, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: t(context).loading,
      child: Container(
        padding: const EdgeInsets.all(MgSpace.s12),
        decoration: BoxDecoration(
          color: dark ? MgColors.white(0.04) : MgColors.surface,
          borderRadius: BorderRadius.circular(MgRadius.card),
          border: Border.all(color: dark ? MgColors.white(0.08) : MgColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgSkeleton(height: imageHeight, radius: 12, dark: dark),
          const SizedBox(height: 12),
          MgSkeleton(width: 180, height: 16, dark: dark),
          const SizedBox(height: 8),
          MgSkeleton(width: 120, height: 12, dark: dark),
        ]),
      ),
    );
  }
}
