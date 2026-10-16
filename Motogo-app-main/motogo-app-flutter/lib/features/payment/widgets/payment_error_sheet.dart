import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/mg_nav_controls.dart';

/// Persistent bottom sheet for payment errors — stays visible until
/// the user taps the action button. Each error scenario gets a specific
/// title, explanation, and clear guidance on what to do next.
class PaymentErrorSheet {
  PaymentErrorSheet._();

  /// Show error bottom sheet. Returns when user dismisses it.
  ///
  /// [dismissible] = false pro terminální stavy (vypršel čas, vyčerpané
  /// pokusy): sheet nejde stáhnout ani zavřít mimo tlačítka — jinak by
  /// zákazník zůstal na mrtvé obrazovce s aktivním „Zaplatit".
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required String buttonLabel,
    VoidCallback? onButton,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool dismissible = true,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: dismissible,
      enableDrag: dismissible,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PopScope(
        canPop: dismissible,
        // Terminální stav: systémové zpět nesmí potichu nic neudělat —
        // provede hlavní krok (do rezervace / vybrat znovu), jako tlačítko.
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          Navigator.of(ctx).pop();
          onButton?.call();
        },
        child: _ErrorSheetContent(
          title: title,
          message: message,
          buttonLabel: buttonLabel,
          onButton: onButton,
          secondaryLabel: secondaryLabel,
          onSecondary: onSecondary,
          dismissible: dismissible,
        ),
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
  final bool dismissible;

  const _ErrorSheetContent({
    required this.title,
    required this.message,
    required this.buttonLabel,
    this.onButton,
    this.secondaryLabel,
    this.onSecondary,
    this.dismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 24),
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
            // Úchyt + vždy viditelný křížek (požadavek majitele: z každého
            // sheetu jde odejít). Terminální stav: křížek = hlavní krok.
            MgSheetHandle(
              barColor: MotoGoColors.g300,
              margin: const EdgeInsets.only(bottom: 8),
              onClose: dismissible
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      onButton?.call();
                    },
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
            Text(
              t(context).tr('psHelpLine'),
              style: const TextStyle(
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
