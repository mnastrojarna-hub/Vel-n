import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// Round map control in the v2 look (white 48 disc + line + shadow, ink /
/// `#0D6E0D` glyph — neon belongs to the record dock). The old Material
/// icon picks the line icon and the screen-reader label; same onTap.
class MapRoundV2 extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const MapRoundV2({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final add = icon == Icons.add_location_alt_outlined || icon == Icons.add_location_alt;
    return MgIconButton(
      icon: add ? MgIcons.pinPlus : MgIcons.gps,
      onTap: onTap,
      style: MgIconButtonStyle.light,
      size: 48,
      iconColor: add ? MgColors.link : MgColors.ink,
      semanticLabel: add ? tr.tr('poiAddPlace') : tr.tr('v2RtMyLocation'),
    );
  }
}

/// Header glyph of the map screens (replaces the emoji).
class MapTitleGlyphV2 extends StatelessWidget {
  final bool routes;
  const MapTitleGlyphV2({super.key, this.routes = false});

  @override
  Widget build(BuildContext context) =>
      MgIcon(routes ? MgIcons.route : MgIcons.compass, size: 20, color: MgColors.neon);
}
