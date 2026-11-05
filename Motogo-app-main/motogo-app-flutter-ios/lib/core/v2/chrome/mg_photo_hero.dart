import 'package:flutter/material.dart';

import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_back_v2.dart';

/// Full-bleed photo / map hero (Detail motorky, rezervace, trasy): bottom
/// scrim, glass controls (`MgV2Back` photo style top-left, [topRight]
/// controls), status pill + tags + H1 + meta on the scrim. Ken Burns one
/// shot 8 s (none under reduced motion). [image] is the caller's image
/// widget (existing `NetImage` / gallery pager) — this never loads images.
class MgPhotoHero extends StatelessWidget {
  final Widget image;
  final double height;
  final VoidCallback? onBack;
  final bool backIsClose;
  final List<Widget> topRight;
  final Widget? statusPill;
  final List<Widget> tags;
  final String? title;
  final String? meta;
  final Widget? bottom;
  final bool kenBurns;

  const MgPhotoHero({
    super.key,
    required this.image,
    this.height = 320,
    this.onBack,
    this.backIsClose = false,
    this.topRight = const [],
    this.statusPill,
    this.tags = const [],
    this.title,
    this.meta,
    this.bottom,
    this.kenBurns = true,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    Widget img = image;
    if (kenBurns && !MgMotion.reduced(context)) {
      img = MgProgressOnce(
        duration: MgMotion.kenBurns,
        curve: Curves.easeOut,
        builder: (_, t) => Transform.scale(scale: 1.06 - 0.06 * t, child: image),
      );
    }
    return SizedBox(
      height: height + top,
      child: Stack(fit: StackFit.expand, children: [
        ClipRect(child: img),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MgColors.nightA(0.35), MgColors.nightA(0), MgColors.nightA(0.55), MgColors.nightA(0.9)],
                stops: const [0, 0.3, 0.65, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: top + 8,
          left: 16,
          right: 16,
          child: Row(children: [
            if (onBack != null) MgV2Back(onTap: onBack, close: backIsClose, style: MgBackStyle.photo),
            const Spacer(),
            for (final w in topRight) ...[const SizedBox(width: 8), w],
          ]),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (statusPill != null || tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [if (statusPill != null) statusPill!, ...tags]),
              ),
            if (title != null)
              Semantics(
                header: true,
                child: Text(title!, style: MgType.h1.copyWith(color: MgColors.onDark, fontWeight: FontWeight.w800)),
              ),
            if (meta != null) ...[
              const SizedBox(height: 4),
              Text(meta!, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
            ],
            if (bottom != null) ...[const SizedBox(height: 8), bottom!],
          ]),
        ),
      ]),
    );
  }
}
