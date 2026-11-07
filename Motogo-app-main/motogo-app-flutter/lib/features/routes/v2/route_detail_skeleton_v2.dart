import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import 'route_detail_view_v2.dart' show RouteDetailViewV2;

/// Route detail while the routes load (F-19): the final geometry — map
/// hero (same height as the detail), the dark stats card overlapping −24
/// with its title bar and 2 × 2 tiles, then a section head and two cards —
/// shimmering (static under reduced motion), photo-style back. After 15 s
/// the same "trvá to déle" note + retry / back as `MgLoadingView`.
class RouteDetailSkeletonV2 extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onRetry;
  const RouteDetailSkeletonV2({super.key, required this.onBack, required this.onRetry});

  @override
  State<RouteDetailSkeletonV2> createState() => _RouteDetailSkeletonV2State();
}

class _RouteDetailSkeletonV2State extends State<RouteDetailSkeletonV2> {
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
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    final mapH = RouteDetailViewV2.mapHeightFor(MediaQuery.sizeOf(context).height) + top;
    Widget tile() => const Expanded(child: MgSkeleton(height: 56, radius: 14, dark: true));
    return MgStatusBar(
      dark: false,
      child: ColoredBox(
        color: MgColors.canvas,
        child: Stack(children: [
          Positioned(left: 0, right: 0, top: 0, height: mapH, child: const MgSkeleton(height: double.infinity, radius: 0)),
          Positioned.fill(
            top: mapH - 24,
            child: ListView(physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero, children: [
              Semantics(
                label: tr.loading,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: MgGradients.dark,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: MgShadows.dark,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const MgSkeleton(width: 84, height: 24, radius: 999, dark: true),
                    const SizedBox(height: 12),
                    const FractionallySizedBox(widthFactor: 0.8, child: MgSkeleton(height: 24, dark: true)),
                    const SizedBox(height: 16),
                    Row(children: [tile(), const SizedBox(width: 8), tile()]),
                    const SizedBox(height: 8),
                    Row(children: [tile(), const SizedBox(width: 8), tile()]),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: _slow
                    ? MgStateBanner(
                        tone: MgTone.pending,
                        title: tr.tr('eoSlowTitle'),
                        text: tr.tr('eoSlowBody'),
                        actions: [
                          MgBtnInk(label: tr.tr('eoRetry'), onTap: widget.onRetry, expand: false, height: 40),
                          MgBtnText(label: tr.tr('eoBack'), onTap: widget.onBack),
                        ],
                      )
                    : const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.9, child: MgSkeleton(height: 14)),
                        SizedBox(height: 8),
                        FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.7, child: MgSkeleton(height: 14)),
                        SizedBox(height: 24),
                        MgSkeletonRow(thumb: 36, lines: 1),
                        SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: MgSkeleton(height: 150, radius: 16)),
                          SizedBox(width: 12),
                          Expanded(child: MgSkeleton(height: 150, radius: 16)),
                        ]),
                      ]),
              ),
            ]),
          ),
          Positioned(top: top + 10, left: 12, child: MgV2Back(onTap: widget.onBack, style: MgBackStyle.photo)),
        ]),
      ),
    );
  }
}
