import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Detail button — matches original CSS: btn-g (green), btn-out (outlined),
/// danger (red bg), sos (light-red bg).
class ResDetailButton extends StatelessWidget {
  final String label;
  final String? emoji;
  final IconData? icon;
  final Color bgColor;
  final Color textColor;
  final Color? iconColor;
  final Color? borderColor;
  final VoidCallback onTap;

  /// Primary green button (btn-g).
  const ResDetailButton.primary({
    super.key,
    required this.label,
    this.emoji,
    this.icon,
    required this.onTap,
  })  : bgColor = MotoGoColors.green,
        textColor = Colors.white,
        iconColor = Colors.white,
        borderColor = null;

  /// Outlined button (btn-out) — white bg, green border.
  const ResDetailButton.outlined({
    super.key,
    required this.label,
    this.emoji,
    this.icon,
    required this.onTap,
    this.iconColor,
  })  : bgColor = Colors.white,
        textColor = MotoGoColors.dark,
        borderColor = MotoGoColors.green;

  /// Red danger button — red bg, white text (cancel reservation).
  const ResDetailButton.danger({
    super.key,
    required this.label,
    this.emoji,
    this.icon,
    required this.onTap,
  })  : bgColor = MotoGoColors.red,
        textColor = Colors.white,
        iconColor = Colors.white,
        borderColor = null;

  /// SOS button — light red bg, dark red text.
  const ResDetailButton.sos({
    super.key,
    required this.label,
    this.emoji,
    this.icon,
    required this.onTap,
  })  : bgColor = const Color(0xFFFEE2E2),
        textColor = const Color(0xFFB91C1C),
        iconColor = const Color(0xFFB91C1C),
        borderColor = null;

  @override
  Widget build(BuildContext context) {
    final hasShadow = bgColor == MotoGoColors.green;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(50),
          border: borderColor != null ? Border.all(color: borderColor!, width: 2) : null,
          boxShadow: hasShadow
              ? [BoxShadow(color: MotoGoColors.green.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji != null) ...[
              Text(emoji!, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
            ] else if (icon != null) ...[
              Icon(icon!, size: 18, color: iconColor ?? textColor),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor, letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
