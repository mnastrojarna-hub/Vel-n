import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Label/value row used in reservation detail info cards.
class ResDetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final bool bold;
  final Color? valueColor;
  const ResDetailRow({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
          ),
          child ?? Text(value ?? '', style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: valueColor ?? MotoGoColors.black)),
        ],
      ),
    );
  }
}
