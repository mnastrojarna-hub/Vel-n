import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Loading slot of the carousel (one shimmer pass while loading).
class FunnelSkeleton extends StatelessWidget {
  const FunnelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h, [double r = 6]) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: MgColors.white(0.08), borderRadius: BorderRadius.circular(r)),
        );
    return ExcludeSemantics(
      child: MgShimmer(
        highlight: MgColors.white(0.13),
        child: Container(
          color: MgColors.panel,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            bar(120, 26, 999),
            const Spacer(),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  bar(170, 18),
                  const SizedBox(height: 8),
                  bar(110, 14),
                ]),
              ),
              bar(96, 26),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Empty / error slot of the carousel (`.fn-emp`): tone disc + title + text.
class FunnelEmptySlot extends StatelessWidget {
  final bool error;
  final String title;
  final String text;
  const FunnelEmptySlot({super.key, required this.error, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [MgColors.panel, MgColors.night],
        ),
      ),
      // Výška podle obsahu (min. 200 v HomeFunnelV2): celé vysvětlení
      // i při velkém písmu, nic se neusekne.
      constraints: const BoxConstraints(minHeight: 200),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Semantics(
        liveRegion: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MgToneDisc(tone: error ? MgTone.err : MgTone.info, size: 48, dark: true, icon: error ? null : MgIcons.calendarX),
          const SizedBox(height: 8),
          MgWordFit(
            minScale: 0.8,
            alignment: Alignment.center,
            child: Text(title, textAlign: TextAlign.center, style: MgType.title.copyWith(color: MgColors.onDark)),
          ),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
        ]),
      ),
    );
  }
}
