import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme.dart';

/// MotoGo24 toast notification — mirrors showT() from ui-toast-helpers.js.
/// Shows a styled snackbar with icon, title, and message.
/// Matches CSS: .toast { background: var(--dark); border-radius: 14px; }
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
          // Icon
          Text(icon, style: const TextStyle(fontSize: 19)),
          const SizedBox(width: MotoGoSpacing.fieldGap),
          // Title + message
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeLg,
                    fontWeight: MotoGoTypo.w700,
                    color: Colors.white,
                  ),
                ),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: MotoGoTypo.sizeMd,
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: MotoGoTypo.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: MotoGoColors.dark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MotoGoRadius.xxl),
      ),
      // Position above bottom nav: 16px sides, 100px from bottom
      margin: EdgeInsets.fromLTRB(
        MotoGoSpacing.screenH,
        0,
        MotoGoSpacing.screenH,
        MotoGoDimens.bnavHeight + MotoGoSpacing.xl,
      ),
      duration: duration,
      elevation: 8,
    ),
  );
}
