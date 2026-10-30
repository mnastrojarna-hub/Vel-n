import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/states/legacy_state_looks.dart' show v2LoadingLook;
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/widgets/mg_skeleton.dart';

/// Loading state of the v2 bike detail (DESIGN_V22: skeletons like Motorky,
/// Trasy, Doklady — never a bare spinner on the canvas): the photo hero and
/// the white sheet with the key tiles and "Tvoje jízda" as shimmering
/// blocks (static under reduced motion). After 15 s the same "trvá to déle"
/// block as `MgLoadingView` with the page's own Zkusit znovu / Zpět.
class DetailLoadingV2 extends StatefulWidget {
  final VoidCallback onRetry;
  final VoidCallback onBack;
  const DetailLoadingV2({super.key, required this.onRetry, required this.onBack});

  @override
  State<DetailLoadingV2> createState() => _DetailLoadingV2State();
}

class _DetailLoadingV2State extends State<DetailLoadingV2> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heroH = (MediaQuery.sizeOf(context).height * 0.42).clamp(240.0, 420.0);
    Widget tile() => const Expanded(child: MgSkeleton(height: 64, radius: 14));
    return Semantics(
      label: t(context).loading,
      child: ColoredBox(
        color: MgColors.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              height: heroH,
              color: MgColors.night,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgSkeleton(width: 120, height: 14, dark: true),
                SizedBox(height: 10),
                MgSkeleton(width: 220, height: 26, radius: 10, dark: true),
              ]),
            ),
            Transform.translate(
              offset: const Offset(0, -22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: const BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: MgColors.grabberLight, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  Row(children: [tile(), const SizedBox(width: 8), tile(), const SizedBox(width: 8), tile()]),
                  const SizedBox(height: 16),
                  const MgSkeleton(height: 200, radius: 20),
                  const SizedBox(height: 16),
                  const MgSkeleton(width: 160, height: 16),
                  const SizedBox(height: 8),
                  const MgSkeleton(height: 12),
                  if (_slow) v2LoadingLook(context, slow: true, onRetry: widget.onRetry, onBack: widget.onBack),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
