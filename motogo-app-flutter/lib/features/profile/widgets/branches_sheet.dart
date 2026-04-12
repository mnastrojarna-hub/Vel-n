import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/supabase_client.dart';
import '../../auth/widgets/toast_helper.dart';

/// Shows a bottom sheet listing all active branches fetched from Supabase.
Future<void> showBranchesSheet(BuildContext context) async {
  try {
    final res = await MotoGoSupabase.client
        .from('branches')
        .select('name, address, city, phone, email, is_open, gps_lat, gps_lng, type')
        .eq('active', true)
        .order('name');
    if (!context.mounted) return;
    final branches = res as List;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Pobočky MotoGo24',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            const SizedBox(height: 16),
            ...branches.map((b) {
              final isOpen = b['is_open'] == true;
              final lat = b['gps_lat'];
              final lng = b['gps_lng'];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MotoGoColors.g200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 36, height: 36, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: MotoGoColors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.motorcycle, size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b['name'] ?? '',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                        Text(
                          '${b['address'] ?? ''}, ${b['city'] ?? ''} · ${b['type'] ?? 'obslužná'}',
                          style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
                        ),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOpen ? MotoGoColors.greenPale : MotoGoColors.redBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOpen ? 'Nonstop' : 'Zavřeno',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isOpen ? MotoGoColors.greenDark : MotoGoColors.red,
                        ),
                      ),
                    ),
                  ]),
                  if (lat != null && lng != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity, height: 40,
                      child: OutlinedButton(
                        onPressed: () => launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lng')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MotoGoColors.greenDark,
                          side: const BorderSide(color: MotoGoColors.green),
                        ),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('🗺️', style: TextStyle(fontSize: 14)),
                          SizedBox(width: 6),
                          Text('Otevřít v mapách', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              );
            }),
          ]),
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showMotoGoToast(context, icon: '✗', title: 'Chyba', message: 'Nepodařilo se načíst pobočky');
    }
  }
}
