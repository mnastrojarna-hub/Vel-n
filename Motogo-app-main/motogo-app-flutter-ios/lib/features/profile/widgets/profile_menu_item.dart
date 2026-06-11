import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Tappable row item used in all menu sections on the Profile screen.
class ProfileMenuItem extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final Color? bgColor;

  const ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.bgColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor ?? MotoGoColors.g100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: labelColor ?? MotoGoColors.black,
                ),
              ),
            ),
            const Text('›', style: TextStyle(fontSize: 16, color: MotoGoColors.g400)),
          ]),
        ),
      );
}
