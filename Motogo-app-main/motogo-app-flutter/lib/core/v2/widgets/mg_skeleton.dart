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

/// List-row skeleton in the final row geometry (thumb + [lines] text lines
/// + optional [trailing] block of that width) — no jump when data arrives.
class MgSkeletonRow extends StatelessWidget {
  final double thumb;
  final double thumbRadius;
  final int lines;
  final bool dark;
  final double? trailing;
  const MgSkeletonRow({
    super.key,
    this.thumb = 56,
    this.thumbRadius = 12,
    this.lines = 2,
    this.dark = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: t(context).loading,
      child: Row(children: [
        if (thumb > 0) ...[
          MgSkeleton(width: thumb, height: thumb, radius: thumbRadius, dark: dark),
          const SizedBox(width: MgSpace.s12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: i == 0 ? 0.7 : 0.45,
                child: MgSkeleton(height: i == 0 ? 15 : 11, dark: dark),
              ),
            ],
          ]),
        ),
        if (trailing != null) ...[
          const SizedBox(width: MgSpace.s12),
          MgSkeleton(width: trailing, height: 20, dark: dark),
        ],
      ]),
    );
  }
}

/// Photo-card skeleton (catalog / route / product cards): photo band of
/// [photoHeight], optional rows of [pills] (their widths), [lines] text
/// lines and an optional CTA block of [ctaHeight].
class MgSkeletonPhotoCard extends StatelessWidget {
  final double photoHeight;
  final int lines;
  final bool dark;
  final double? ctaHeight;
  final double radius;
  final List<double> pills;
  const MgSkeletonPhotoCard({
    super.key,
    required this.photoHeight,
    this.lines = 2,
    this.dark = false,
    this.ctaHeight,
    this.radius = 16,
    this.pills = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: t(context).loading,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: dark ? MgColors.white(0.04) : MgColors.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: dark ? MgColors.white(0.08) : MgColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          MgSkeleton(height: photoHeight, radius: 0, dark: dark),
          Padding(
            padding: const EdgeInsets.all(MgSpace.s12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (pills.isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final w in pills) MgSkeleton(width: w, height: 24, radius: 999, dark: dark),
                ]),
                const SizedBox(height: 10),
              ],
              for (var i = 0; i < lines; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: i == 0 ? 0.65 : 0.4,
                  child: MgSkeleton(height: i == 0 ? 16 : 12, dark: dark),
                ),
              ],
              if (ctaHeight != null) ...[
                const SizedBox(height: MgSpace.s12),
                MgSkeleton(height: ctaHeight!, radius: 14, dark: dark),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
