import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme.dart';

/// Location row widget showing pickup/return location with optional navigation.
class ResLocationRow extends StatelessWidget {
  final String label;
  final bool isDelivery;
  final String? address;
  final double? lat;
  final double? lng;
  final String? fallbackAddress;

  const ResLocationRow({
    super.key,
    required this.label,
    required this.isDelivery,
    this.address,
    this.lat,
    this.lng,
    this.fallbackAddress,
  });

  Future<void> _openNavigation() async {
    // Try GPS coordinates first, then fall back to address search
    Uri? uri;
    if (lat != null && lng != null) {
      // Use geo URI which lets the user choose their preferred maps app
      // On Android opens chooser, on iOS opens Apple Maps by default
      uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        // Fallback to Google Maps URL (works on both platforms)
        uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (fallbackAddress != null && fallbackAddress!.isNotEmpty) {
      final encoded = Uri.encodeComponent(fallbackAddress!);
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = isDelivery ? 'Přistavení' : 'Pobočka';
    final icon = isDelivery ? Icons.local_shipping_outlined : Icons.store_outlined;
    final displayAddress = address ?? '–';
    final hasNavTarget = (lat != null && lng != null) ||
        (fallbackAddress != null && fallbackAddress!.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.g400),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MotoGoColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MotoGoColors.g200),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: MotoGoColors.greenDarker),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeLabel,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.black),
                      ),
                      if (displayAddress != '–')
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            displayAddress,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.g600),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasNavTarget)
                  GestureDetector(
                    onTap: _openNavigation,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: MotoGoColors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.navigation_outlined, size: 18, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
