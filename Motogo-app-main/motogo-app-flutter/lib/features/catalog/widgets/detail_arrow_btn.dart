import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Carousel arrow button used on the moto detail image gallery.
class DetailArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const DetailArrowBtn({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: MotoGoColors.dark.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      );
}
