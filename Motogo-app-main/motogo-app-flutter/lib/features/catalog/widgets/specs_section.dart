import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';

/// Specs grid (2-column) shown on the moto detail screen.
class SpecsSection extends StatelessWidget {
  final List<MapEntry<String, String>> specs;
  const SpecsSection({super.key, required this.specs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: MotoGoColors.black.withValues(alpha: 0.06),
            blurRadius: 12,
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.build_outlined, size: 16, color: MotoGoColors.g400),
          const SizedBox(width: 6),
          Text(
            t(context).tr('specsTitle'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MotoGoColors.g400,
              letterSpacing: 0.5,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 8,
          children: specs
              .map((s) => Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MotoGoColors.g100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.key.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: MotoGoColors.g400,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.value,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: MotoGoColors.black,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}
