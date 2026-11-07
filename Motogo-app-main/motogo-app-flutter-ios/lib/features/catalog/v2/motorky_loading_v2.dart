import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/states/legacy_state_looks.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';

/// Motorky list while the catalogue loads (CB-08): skeletons in the final
/// card geometry (2 dark full cards of [cardHeight], or 4 light grid
/// cards) + "Načítám motorky…" — no layout jump when the cards arrive.
/// After 15 s the SAME slow state as `MgLoadingView` ("trvá to déle" +
/// [onRetry] = the screen's existing reload).
class MotorkyLoadingV2 extends StatefulWidget {
  final bool grid;
  final double cardHeight;
  final VoidCallback onRetry;
  const MotorkyLoadingV2({super.key, required this.grid, required this.cardHeight, required this.onRetry});

  /// Text + pills + CTA block under the photo of the full-card skeleton.
  static const double fullBody = 160;

  @override
  State<MotorkyLoadingV2> createState() => _MotorkyLoadingV2State();
}

class _MotorkyLoadingV2State extends State<MotorkyLoadingV2> {
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
  Widget build(BuildContext context) {
    if (_slow) return v2LoadingLook(context, slow: true, onRetry: widget.onRetry);
    final tr = t(context);
    final label = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Semantics(
        liveRegion: true,
        child: Text(tr.tr('v2UxCbLoadingMotos').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
      ),
    );
    if (widget.grid) {
      Widget cell() => const MgSkeletonPhotoCard(photoHeight: 150, lines: 3, pills: [72]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label,
        for (var r = 0; r < 2; r++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(child: cell()),
              const SizedBox(width: MgSpace.s12),
              Expanded(child: cell()),
            ]),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      label,
      for (var i = 0; i < 2; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ColoredBox(
            color: MgColors.night,
            child: MgSkeletonPhotoCard(
              photoHeight: widget.cardHeight - MotorkyLoadingV2.fullBody,
              dark: true,
              radius: 0,
              pills: const [88, 56, 110],
              ctaHeight: 52,
            ),
          ),
        ),
    ]);
  }
}
