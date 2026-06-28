import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'routes_model.dart';

/// Spodní panel s detailem bodu zájmu — zobrazí se po kliknutí na bod (na mapě
/// i v navigaci): galerie fotek (klik = zvětšit přes celou obrazovku s
/// přibližováním), název a krátký popis (lokalizovaný).
void showRoutePoiSheet(BuildContext context, RoutePoi poi, String lang, {int? index}) {
  final desc = poi.descFor(lang);
  // Všechny fotky bodu (titulní + galerie), bez duplicit, v pořadí.
  final imgs = <String>{
    if (poi.imageUrl != null && poi.imageUrl!.isNotEmpty) poi.imageUrl!,
    ...poi.images.where((e) => e.isNotEmpty),
  }.toList();

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imgs.isNotEmpty)
          GestureDetector(
            onTap: () => _openImageViewer(context, imgs, 0),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                children: [
                  Image.network(
                    imgs.first,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: MotoGoColors.greenPale,
                      child: const Center(child: Text('📍', style: TextStyle(fontSize: 34))),
                    ),
                  ),
                  // Náznak „klikni pro zvětšení"
                  Positioned(
                    right: 12, top: 12,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_out_map, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),

        // Galerie miniatur (od druhé fotky)
        if (imgs.length > 1)
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              itemCount: imgs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openImageViewer(context, imgs, i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imgs[i],
                    width: 84, height: 60, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 84, color: MotoGoColors.greenPale,
                      child: const Center(child: Text('📍')),
                    ),
                  ),
                ),
              ),
            ),
          ),

        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(c).padding.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (index != null) ...[
                    Container(
                      width: 26, height: 26,
                      decoration: const BoxDecoration(color: MotoGoColors.greenDarker, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${index + 1}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      poi.nameFor(lang),
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeH2,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              if (desc != null && desc.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeLg,
                    height: 1.5,
                    color: MotoGoColors.g600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Fullscreen prohlížeč fotek bodu zájmu — listování (PageView) + přibližování
/// prsty (InteractiveViewer). Zavře se křížkem nebo tapnutím mimo.
void _openImageViewer(BuildContext context, List<String> imgs, int start) {
  showDialog(
    context: context,
    barrierColor: Colors.black,
    builder: (dctx) {
      final controller = PageController(initialPage: start);
      return Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: imgs.length,
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  imgs[i],
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Text('📍', style: TextStyle(fontSize: 48))),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(dctx).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(dctx).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
          if (imgs.length > 1)
            Positioned(
              bottom: MediaQuery.of(dctx).padding.bottom + 16,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${imgs.length} foto',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
