import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/collapsible_section.dart';
import '../../core/widgets/net_image.dart';
import '../catalog/widgets/fullscreen_gallery.dart';
import 'branches_info_provider.dart';
import 'branches_widgets.dart';
import '../../core/v2/flag/v2_scope.dart';
import '../../core/v2/icons/mg_icon.dart';
import '../../core/v2/widgets/mg_word_fit.dart';
import 'v2/branches_v2_parts.dart';

/// „Fotky pobočky“ v detailu pobočky (výchozí zabalené): náhledy 2 vedle sebe
/// s přeloženým popiskem, klepnutí otevře fotku v plné velikosti (zoom,
/// listování). Fotky = web `gfx/pobocky/<slug>/` ([branchesInfoGallery]).
class BranchPhotosSection extends StatelessWidget {
  final List<BranchPhoto> photos;
  const BranchPhotosSection({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final full = [for (final p in photos) p.fullUrl];
    final rows = <Widget>[];
    for (var i = 0; i < photos.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _tile(context, i, full)),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < photos.length ? _tile(context, i + 1, full) : const SizedBox.shrink()),
        ]),
      ));
    }
    // v2 vzhled (kill-switch app_v2_ui): stejné náhledy a galerie, jiná karta.
    if (MgV2.on(context)) {
      return BranchCollapsibleV2(icon: MgIcons.image, title: t(context).tr('branchPhotos'), children: rows);
    }
    return CollapsibleSection(
      emoji: '📷',
      title: t(context).tr('branchPhotos'),
      decoration: branchesCardDecoration(),
      padding: const EdgeInsets.all(16),
      children: rows,
    );
  }

  Widget _tile(BuildContext context, int i, List<String> full) => GestureDetector(
        onTap: () => FullscreenGallery.open(context, images: full, initialIndex: i),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: MgImage(
                photos[i].thumbUrl,
                thumbWidth: 640,
                fit: BoxFit.cover,
                error: Container(
                  color: MotoGoColors.g100,
                  child: const Center(child: Icon(Icons.image_not_supported_outlined, color: MotoGoColors.g400)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _caption(context, Text(t(context).tr(photos[i].captionKey),
              style: const TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w600, color: MotoGoColors.g600))),
        ]),
      );

  // v2: dlouhé slovo popisku (uk „самообслуговування“) se zmenší, nezlomí.
  Widget _caption(BuildContext context, Text text) =>
      MgV2.on(context) ? MgWordFit(minScale: 0.7, child: text) : text;
}
