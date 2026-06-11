import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Pill-shaped chip used in the license group filter row.
class LicenseChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const LicenseChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? MotoGoColors.green : Colors.white,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: active ? MotoGoColors.green : MotoGoColors.g200,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.black : MotoGoColors.black,
          ),
        ),
      ),
    );
  }
}
