import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../moto_model.dart';

/// Full-width motorcycle card — 1:1 replica of Capacitor MotoGo24 design.
/// Shows image carousel, specs badges, description, price, and detail button.
class MotoCard extends StatefulWidget {
  final Motorcycle moto;
  final VoidCallback onTap;

  const MotoCard({super.key, required this.moto, required this.onTap});

  @override
  State<MotoCard> createState() => _MotoCardState();
}

class _MotoCardState extends State<MotoCard> {
  int _currentImageIndex = 0;

  List<String> get _images {
    if (widget.moto.images.isNotEmpty) return widget.moto.images;
    if (widget.moto.imageUrl != null) return [widget.moto.imageUrl!];
    return [];
  }

  void _nextImage() {
    if (_images.length <= 1) return;
    setState(() => _currentImageIndex = (_currentImageIndex + 1) % _images.length);
  }

  void _prevImage() {
    if (_images.length <= 1) return;
    setState(() => _currentImageIndex = (_currentImageIndex - 1 + _images.length) % _images.length);
  }

  @override
  Widget build(BuildContext context) {
    final moto = widget.moto;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: MotoGoColors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image section with carousel
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Stack(
              children: [
                // Main image
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _images.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _images[_currentImageIndex],
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: MotoGoColors.g200,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: MotoGoColors.green,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: MotoGoColors.g200,
                            child: const Icon(
                              Icons.motorcycle,
                              size: 48,
                              color: MotoGoColors.g400,
                            ),
                          ),
                        )
                      : Container(
                          color: MotoGoColors.g200,
                          child: const Icon(
                            Icons.motorcycle,
                            size: 48,
                            color: MotoGoColors.g400,
                          ),
                        ),
                ),

                // Model name overlay (top-left)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.65,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: MotoGoColors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        moto.model,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),

                // "DNES VOLNÁ" badge (bottom-right)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: MotoGoColors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          t(context).tr('motoCardAvailableToday'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Image carousel arrows
                if (_images.length > 1) ...[
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _prevImage,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_left, size: 20, color: MotoGoColors.black),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _nextImage,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_right, size: 20, color: MotoGoColors.black),
                        ),
                      ),
                    ),
                  ),
                ],

                // Image indicator dots
                if (_images.length > 1)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_images.length, (i) => Container(
                        width: i == _currentImageIndex ? 8 : 6,
                        height: i == _currentImageIndex ? 8 : 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _currentImageIndex
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                      )),
                    ),
                  ),
              ],
            ),
          ),

          // Info section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Spec badges row
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (moto.licenseRequired != null)
                      _SpecBadge(
                        label: '${t(context).tr('motoCardLicensePrefix')}${moto.licenseRequired!}',
                        color: MotoGoColors.greenDark,
                      ),
                    if (moto.category != null)
                      _SpecBadge(
                        label: _categoryLabel(context, moto.category!).toUpperCase(),
                        color: MotoGoColors.black,
                      ),
                    if (moto.powerKw != null)
                      _SpecBadge(
                        label: '${moto.powerKw} KW',
                        color: MotoGoColors.black,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Branch name
                if (moto.branchName != null)
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: MotoGoColors.red),
                      const SizedBox(width: 4),
                      Text(
                        moto.branchName!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: MotoGoColors.red,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),

                // Description / features
                if (moto.description != null || moto.features.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  if (moto.description != null)
                    _FeatureLine(text: moto.description!),
                  ...moto.features.take(2).map((f) => _FeatureLine(text: f)),
                ],

                const SizedBox(height: 14),

                // Price + Detail button row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Price
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'od ${moto.priceLabel}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: MotoGoColors.black,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          t(context).tr('motoCardPricePerDay'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: MotoGoColors.g400,
                          ),
                        ),
                      ],
                    ),

                    // Detail button
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: MotoGoColors.green,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t(context).tr('motoCardDetail'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  String _categoryLabel(BuildContext context, String cat) {
    final map = {
      'cestovni': t(context).tr('motoCardCategoryTravel'),
      'detske': t(context).tr('motoCardCategoryChildren'),
      'sportovni': t(context).tr('motoCardCategorySport'),
      'naked': t(context).tr('motoCardCategoryNaked'),
      'chopper': t(context).tr('motoCardCategoryChopper'),
      'supermoto': t(context).tr('motoCardCategorySupermoto'),
    };
    return map[cat] ?? cat;
  }
}

class _SpecBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SpecBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  final String text;
  const _FeatureLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '> ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: MotoGoColors.g400,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: MotoGoColors.g600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
