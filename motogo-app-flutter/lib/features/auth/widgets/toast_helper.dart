import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme.dart';

/// MotoGo24 toast notification — mirrors showT() from ui-toast-helpers.js.
/// Shows a styled snackbar with icon, title, and message.
/// Includes haptic feedback — mirrors Haptics.impact({style:'LIGHT'}) from native-bridge.js.
void showMotoGoToast(
  BuildContext context, {
  required String icon,
  required String title,
  String message = '',
  Duration duration = const Duration(seconds: 3),
}) {
  // Haptic feedback — matches Capacitor Haptics.impact({style: 'LIGHT'})
  HapticFeedback.lightImpact();

  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 19)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: MotoGoColors.dark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      duration: duration,
    ),
  );
}
