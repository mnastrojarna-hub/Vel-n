import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/widgets/net_image.dart';

/// Bike photo (cover) or a dark placeholder with the bike glyph — never
/// throws, never shows a broken image.
class HomePhoto extends StatelessWidget {
  final String? url;
  final int thumbWidth;

  /// Bike glyph on the placeholder (off for route covers under a sketch).
  final bool glyph;
  const HomePhoto({super.key, this.url, this.thumbWidth = 800, this.glyph = true});

  @override
  Widget build(BuildContext context) {
    final ph = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [MgColors.glow, MgColors.panel, MgColors.night],
          stops: [0, 0.55, 1],
        ),
      ),
      child: glyph ? Center(child: MgIcon(MgIcons.moto, size: 44, color: MgColors.neonA(0.33))) : null,
    );
    final u = url?.trim() ?? '';
    if (u.isEmpty) return SizedBox.expand(child: ph);
    return SizedBox.expand(
      child: MgImage(u, thumbWidth: thumbWidth, fit: BoxFit.cover, placeholder: ph, error: ph),
    );
  }
}
