import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// A single horizontal line used inside the hamburger menu icon button.
class MenuLine extends StatelessWidget {
  final double width;
  const MenuLine({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
