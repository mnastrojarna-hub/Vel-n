import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Shipping method selection card (post / pickup).
class ShipCard extends StatelessWidget {
  final String icon;
  final String label;
  final String sublabel;
  final bool active;
  final VoidCallback onTap;

  const ShipCard({
    super.key,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? MotoGoColors.greenPale : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
            border: Border.all(
                color: active ? MotoGoColors.green : MotoGoColors.g200,
                width: 2),
          ),
          child: Column(children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.black),
                textAlign: TextAlign.center),
            Text(sublabel,
                style:
                    const TextStyle(fontSize: 11, color: MotoGoColors.g400),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}
