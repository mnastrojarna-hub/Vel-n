import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../moto_model.dart';

/// Motorcycle grid card — mirrors the mCard() function from templates-screens.js.
class MotoCard extends StatelessWidget {
  final Motorcycle moto;
  final VoidCallback onTap;

  const MotoCard({super.key, required this.moto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
          boxShadow: [
            BoxShadow(
              color: MotoGoColors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image with gradient overlay
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(MotoGoTheme.radiusLg),
              ),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: CachedNetworkImage(
                      imageUrl: moto.displayImage,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: MotoGoColors.g200,
                        child: const Center(
                          child: Text('🏍️', style: TextStyle(fontSize: 32)),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: MotoGoColors.g200,
                        child: const Center(
                          child: Text('🏍️', style: TextStyle(fontSize: 32)),
                        ),
                      ),
                    ),
                  ),
                  // Bottom gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            MotoGoColors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Name overlay
                  Positioned(
                    bottom: 8,
                    left: 10,
                    right: 10,
                    child: Text(
                      moto.model,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // License badge
                  if (moto.licenseRequired != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: MotoGoColors.dark.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          moto.licenseRequired!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: MotoGoColors.green,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Bottom info
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Category + branch
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (moto.category != null)
                          Text(
                            _categoryLabel(moto.category!),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: MotoGoColors.g400,
                            ),
                          ),
                        if (moto.branchName != null)
                          Text(
                            moto.branchName!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: MotoGoColors.g400,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        moto.priceLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: MotoGoColors.black,
                        ),
                      ),
                      const Text(
                        '/den',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: MotoGoColors.g400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String cat) {
    const map = {
      'cestovni': 'Cestovní / Enduro',
      'detske': 'Dětské',
      'sportovni': 'Sportovní',
      'naked': 'Naked',
      'chopper': 'Chopper',
      'supermoto': 'Supermoto',
    };
    return map[cat] ?? cat;
  }
}
