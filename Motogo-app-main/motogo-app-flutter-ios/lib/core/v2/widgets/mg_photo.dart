import 'package:flutter/material.dart';

import '../../widgets/net_image.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';

/// Every network photo of the v2 look (design D6): server thumb +
/// `memCacheWidth` (via `MgImage`), a fixed box ([aspectRatio] or
/// [width] / [height]) so nothing jumps when it loads, a placeholder in the
/// surface colour (well + glyph on light, panel `#0E2A1C` on [dark] — never a
/// light flash on a dark screen), fade-in 150 ms (0 under reduced motion);
/// a failed load keeps the same box with the glyph.
class MgPhoto extends StatelessWidget {
  final String url;
  final int thumbWidth;
  final BoxFit fit;
  final double? aspectRatio;
  final double? width;
  final double? height;
  final bool dark;
  final String glyph;
  final BorderRadius? borderRadius;
  final Alignment alignment;

  const MgPhoto({
    super.key,
    required this.url,
    this.thumbWidth = 800,
    this.fit = BoxFit.cover,
    this.aspectRatio,
    this.width,
    this.height,
    this.dark = false,
    this.glyph = MgIcons.image,
    this.borderRadius,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final box = ColoredBox(
      color: dark ? MgColors.panel : MgColors.well,
      child: Center(
        child: MgIcon(glyph, size: 24, color: dark ? MgColors.white(0.24) : MgColors.meta.withValues(alpha: 0.5)),
      ),
    );
    final placeholder = SizedBox(width: width, height: height, child: box);
    Widget img = url.isEmpty
        ? placeholder
        : MgImage(
            url,
            thumbWidth: thumbWidth,
            fit: fit,
            width: width,
            height: height,
            alignment: alignment,
            fadeIn: MgMotion.of(context, const Duration(milliseconds: 150)),
            placeholder: placeholder,
            error: placeholder,
          );
    if (borderRadius != null) img = ClipRRect(borderRadius: borderRadius!, child: img);
    if (aspectRatio != null) img = AspectRatio(aspectRatio: aspectRatio!, child: img);
    return img;
  }
}
