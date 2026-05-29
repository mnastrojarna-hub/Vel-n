import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Compact list of motorcycles available at a branch.
/// Displayed inside the expanded [BranchDetailCard].
class BranchMotoList extends StatelessWidget {
  final List<Map<String, dynamic>> motorcycles;
  final bool isSelfService;

  const BranchMotoList({
    required this.motorcycles,
    required this.isSelfService,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(children: [
            const Icon(Icons.motorcycle, size: 16, color: MotoGoColors.greenDark),
            const SizedBox(width: 6),
            Text(
              '${t(context).tr('branchMotosTitle')} (${motorcycles.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.black,
              ),
            ),
            if (isSelfService) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: MotoGoColors.amberBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  t(context).tr('max8Motos'),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.amber,
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          // Motorcycle rows
          ...motorcycles.map((m) => _buildMotoRow(context, m)),
        ],
      ),
    );
  }

  Widget _buildMotoRow(BuildContext context, Map<String, dynamic> m) {
    final images = m['images'] as List?;
    final imageUrl = (images != null && images.isNotEmpty)
        ? images.first as String
        : m['image_url'] as String?;
    final category = m['category'] as String?;
    final license = m['license_required'] as String?;
    final powerKw = m['power_kw'] as num?;
    final engineCc = m['engine_cc'] as num?;
    final motoId = m['id']?.toString();

    return GestureDetector(
      onTap: motoId != null
          ? () {
              Navigator.of(context).pop(); // close the bottom sheet
              context.push('/moto/$motoId');
            }
          : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MotoGoColors.g100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: imageUrl != null
              ? Image.network(
                  imageUrl,
                  width: 56,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
        ),
        const SizedBox(width: 10),
        // Name + specs
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m['brand'] ?? ''} ${m['model'] ?? ''}'.trim(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MotoGoColors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _specLine(context, engineCc, powerKw, license, category),
                style: const TextStyle(
                  fontSize: 10,
                  color: MotoGoColors.g400,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Active indicator
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: MotoGoColors.green,
            shape: BoxShape.circle,
          ),
        ),
      ]),
    ),
    );
  }

  static Widget _placeholder() {
    return Container(
      width: 56,
      height: 40,
      decoration: BoxDecoration(
        color: MotoGoColors.g200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.motorcycle, size: 20, color: MotoGoColors.g400),
    );
  }

  static String _specLine(BuildContext context,
      num? engineCc, num? powerKw, String? license, String? category) {
    final parts = <String>[
      if (engineCc != null) '${engineCc}cc',
      if (powerKw != null) '${powerKw}kW',
      if (license != null) '${t(context).tr('licenseShort')} $license',
      if (category != null) _categoryLabel(context, category),
    ];
    return parts.join(' · ');
  }

  static String _categoryLabel(BuildContext context, String cat) {
    const keys = {
      'cestovni': 'catTouring',
      'detske': 'motoCardCategoryChildren',
      'sportovni': 'motoCardCategorySport',
      'naked': 'motoCardCategoryNaked',
      'chopper': 'motoCardCategoryChopper',
      'supermoto': 'motoCardCategorySupermoto',
    };
    final k = keys[cat];
    return k != null ? t(context).tr(k) : cat;
  }
}
