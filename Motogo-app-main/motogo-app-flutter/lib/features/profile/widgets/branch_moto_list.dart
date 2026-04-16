import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';

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
              'Motorky na pobočce (${motorcycles.length})',
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
                child: const Text(
                  'Max 8 motorek',
                  style: TextStyle(
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
                _specLine(engineCc, powerKw, license, category),
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

  static String _specLine(
      num? engineCc, num? powerKw, String? license, String? category) {
    final parts = <String>[
      if (engineCc != null) '${engineCc}cc',
      if (powerKw != null) '${powerKw}kW',
      if (license != null) 'ŘP $license',
      if (category != null) _categoryLabel(category),
    ];
    return parts.join(' · ');
  }

  static String _categoryLabel(String cat) {
    const labels = {
      'cestovni': 'Cestovní',
      'detske': 'Dětské',
      'sportovni': 'Sportovní',
      'naked': 'Naked',
      'chopper': 'Chopper',
      'supermoto': 'Supermoto',
    };
    return labels[cat] ?? cat;
  }
}
