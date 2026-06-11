import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme.dart';

/// Persistent bottom sheet for payment errors — stays visible until
/// the user taps the action button. Each error scenario gets a specific
/// title, explanation, and clear guidance on what to do next.
class PaymentErrorSheet {
  PaymentErrorSheet._();

  /// Show error bottom sheet. Returns when user dismisses it.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required String buttonLabel,
    VoidCallback? onButton,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ErrorSheetContent(
        title: title,
        message: message,
        buttonLabel: buttonLabel,
        onButton: onButton,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
      ),
    );
  }
}

class _ErrorSheetContent extends StatelessWidget {
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback? onButton;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _ErrorSheetContent({
    required this.title,
    required this.message,
    required this.buttonLabel,
    this.onButton,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 28, 24, MediaQuery.of(context).padding.bottom + 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: MotoGoColors.g300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Red error icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: MotoGoColors.redBg,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('\u2717',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: MotoGoColors.red)),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              title,
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeH1,
                fontWeight: MotoGoTypo.w900,
                color: MotoGoColors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Message (scrollable for long errors)
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeBase,
                    fontWeight: MotoGoTypo.w600,
                    color: MotoGoColors.g600,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Primary action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onButton?.call();
                },
                child: Text(buttonLabel),
              ),
            ),

            // Optional secondary action
            if (secondaryLabel != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onSecondary?.call();
                  },
                  child: Text(
                    secondaryLabel!,
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      fontWeight: MotoGoTypo.w700,
                      color: MotoGoColors.g500,
                    ),
                  ),
                ),
              ),
            ],

            // Support contact
            const SizedBox(height: 16),
            const Text(
              'Pot\u0159ebujete pomoc? Napi\u0161te n\u00e1m na info@motogo24.cz',
              style: TextStyle(
                fontSize: MotoGoTypo.sizeSm,
                fontWeight: MotoGoTypo.w500,
                color: MotoGoColors.g400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
