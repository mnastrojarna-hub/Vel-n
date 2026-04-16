import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../moto_model.dart';

/// Card displaying the motorcycle manual PDF with open/download actions.
class ManualCard extends StatelessWidget {
  final Motorcycle moto;
  const ManualCard({super.key, required this.moto});

  @override
  Widget build(BuildContext context) {
    final fileName = moto.manualUrl?.split('/').last ?? t(context).tr('manualDefaultTitle');

    void openManual(LaunchMode mode) {
      if (moto.manualUrl != null) {
        launchUrl(Uri.parse(moto.manualUrl!), mode: mode);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(context).tr('manualNotAvailable')),
          duration: const Duration(seconds: 2),
        ));
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: MotoGoColors.black.withValues(alpha: 0.06),
            blurRadius: 12,
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.menu_book_outlined, size: 16, color: MotoGoColors.dark),
          const SizedBox(width: 6),
          Text(
            t(context).tr('manualTitle'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MotoGoColors.dark,
              letterSpacing: 0.3,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          fileName,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: MotoGoColors.black,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _ManualBtn(
            icon: Icons.visibility_outlined,
            label: t(context).tr('manualView'),
            onTap: () => openManual(LaunchMode.inAppBrowserView),
          ),
          const SizedBox(width: 8),
          _ManualBtn(
            icon: Icons.search,
            label: t(context).tr('manualSearch'),
            onTap: () => openManual(LaunchMode.inAppBrowserView),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => openManual(LaunchMode.externalApplication),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.download, size: 18, color: Colors.black),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ManualBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ManualBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: MotoGoColors.g100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: MotoGoColors.g600),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: MotoGoColors.g600,
                ),
              ),
            ]),
          ),
        ),
      );
}
