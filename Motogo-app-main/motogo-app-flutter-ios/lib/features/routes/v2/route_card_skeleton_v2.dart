import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../catalog/v2/bike_screen_list_v2.dart' show bikeScreenHeight;

/// Trasy loading (5.0.1): the final geometry of the list — a light band
/// with the toolbar, then one night full-screen route card (media, two
/// place tiles, name, meta) shimmering. No layout jump when data comes.
class RouteScreenSkeletonV2 extends StatelessWidget {
  const RouteScreenSkeletonV2({super.key});

  @override
  Widget build(BuildContext context) {
    final h = bikeScreenHeight(context);
    return Semantics(
      label: t(context).loading,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          color: MgColors.surface,
          child: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: MgSkeleton(height: 40)),
              SizedBox(width: 16),
              Expanded(child: MgSkeleton(height: 40)),
            ]),
            SizedBox(height: 14),
            Row(children: [
              MgSkeleton(width: 96, height: 44, radius: 22),
              SizedBox(width: 8),
              MgSkeleton(width: 150, height: 44, radius: 22),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          height: h,
          color: MgColors.night,
          child: LayoutBuilder(
            builder: (context, c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MgSkeleton(dark: true, radius: 0, height: c.maxHeight * 0.5),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: MgSkeleton(dark: true, height: 84, radius: 12)),
                    SizedBox(width: 10),
                    Expanded(child: MgSkeleton(dark: true, height: 84, radius: 12)),
                  ]),
                  SizedBox(height: 16),
                  MgSkeleton(dark: true, height: 24, width: 240),
                  SizedBox(height: 10),
                  MgSkeleton(dark: true, height: 16, width: 160),
                  SizedBox(height: 14),
                  MgSkeleton(dark: true, height: 18, width: 220),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
