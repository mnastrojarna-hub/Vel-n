import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'routes_model.dart';

/// Spodní panel s detailem bodu zájmu — zobrazí se po kliknutí na bod (na mapě
/// i v navigaci): foto, název a krátký popis (lokalizovaný).
void showRoutePoiSheet(BuildContext context, RoutePoi poi, String lang, {int? index}) {
  final cover = poi.cover;
  final desc = poi.descFor(lang);
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
        if (cover != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Image.network(
              cover,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 110,
                color: MotoGoColors.greenPale,
                child: const Center(child: Text('📍', style: TextStyle(fontSize: 34))),
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
