import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/v2/states/legacy_state_looks.dart' show v2LoadingLook;
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';

/// Loading look in the final layout's geometry (design M5): [skeleton]
/// shimmers while loading; never stuck silently — after 15 s the same
/// "takes longer" block as `MgLoadingView` (retry / back = the screen's
/// existing actions) appears under it.
class ResSkeletonV2 extends StatefulWidget {
  final Widget skeleton;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  const ResSkeletonV2({super.key, required this.skeleton, this.onRetry, this.onBack});

  @override
  State<ResSkeletonV2> createState() => _ResSkeletonV2State();
}

class _ResSkeletonV2State extends State<ResSkeletonV2> {
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_slow) v2LoadingLook(context, slow: true, onRetry: widget.onRetry, onBack: widget.onBack),
        widget.skeleton,
      ]);
}

/// Two reservation cards (156 photo, 3 info lines, 48 action bar) — the
/// list's loading look (RP-13).
class ResListSkeletonV2 extends StatelessWidget {
  final VoidCallback? onRetry;
  const ResListSkeletonV2({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => ResSkeletonV2(
        onRetry: onRetry,
        skeleton: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgSkeletonPhotoCard(photoHeight: 156, lines: 3, ctaHeight: 48),
          SizedBox(height: 12),
          MgSkeletonPhotoCard(photoHeight: 156, lines: 3, ctaHeight: 48),
        ]),
      );
}

/// Edit loading (RP-13): the "TEĎ" summary bar and the chooser's 2-column
/// grid of intent tiles, in their final geometry.
class ResEditSkeletonV2 extends StatelessWidget {
  final VoidCallback? onBack;
  const ResEditSkeletonV2({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    Widget tile() => Container(
          height: 112,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgSkeleton(width: 24, height: 24, radius: 8),
            SizedBox(height: 12),
            MgSkeleton(width: 96, height: 14),
            SizedBox(height: 8),
            MgSkeleton(height: 10),
            SizedBox(height: 6),
            MgSkeleton(width: 72, height: 10),
          ]),
        );
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: ResSkeletonV2(
        onBack: onBack,
        skeleton: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const MgSkeleton(height: 48, radius: 14),
          const SizedBox(height: 16),
          const MgSkeleton(width: 220, height: 12),
          const SizedBox(height: 12),
          for (var r = 0; r < 4; r++) ...[
            if (r > 0) const SizedBox(height: 12),
            Row(children: [Expanded(child: tile()), const SizedBox(width: 12), Expanded(child: tile())]),
          ],
        ]),
      ),
    );
  }
}
