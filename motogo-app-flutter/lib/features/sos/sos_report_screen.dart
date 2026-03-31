import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_provider.dart';

/// SOS main screen — mirrors s-sos from templates-res-sos.js.
/// Shows incident type selection, active incident banner, contact info.
class SosReportScreen extends ConsumerWidget {
  const SosReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeSosProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🆘 SOS — Pomoc na cestě', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                      Text('Vyberte typ problému', style: TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Active incident banner
              activeAsync.when(
                data: (inc) {
                  if (inc == null || !inc.isActive || !inc.isSerious) return const SizedBox.shrink();
                  return _ActiveBanner(incident: inc);
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // AI Agent card
              GestureDetector(
                onTap: () => context.push(Routes.aiAgent),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [MotoGoColors.dark, Color(0xFF2D4A35)]),
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  ),
                  child: const Row(
                    children: [
                      Text('🤖', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI Servisní agent', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text('Diagnostika závad, kontrolky, rady', style: TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      )),
                      Text('›', style: TextStyle(fontSize: 20, color: MotoGoColors.green)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Incident types
              _SosOption(
                icon: '💥', title: 'Nehoda / Krádež',
                subtitle: 'Nahlásit nehodu nebo krádež motorky',
                color: const Color(0xFFFEE2E2),
                onTap: () => _showAccidentPicker(context, ref),
              ),
              const SizedBox(height: 8),
              _SosOption(
                icon: '🔧', title: 'Porucha na cestě',
                subtitle: 'Motorka nefunguje nebo má závadu',
                color: const Color(0xFFFEF3C7),
                onTap: () => _showBreakdownPicker(context, ref),
              ),
              const SizedBox(height: 8),
              _SosOption(
                icon: '📍', title: 'Sdílet polohu',
                subtitle: 'Odeslat GPS pozici MotoGo24',
                color: const Color(0xFFE8FFE8),
                onTap: () => _shareLocation(context, ref),
              ),
              const SizedBox(height: 20),

              // Contact info
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.g200),
                ),
                child: const Row(
                  children: [
                    Text('📞', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nonstop linka MotoGo24', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                        Text('+420 774 256 271', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
                      ],
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccidentPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Typ nehody', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _PickerItem(icon: '🎯', label: 'Lehká nehoda — pokračuji v jízdě',
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.accidentMinor, 'Lehká nehoda'); }),
              _PickerItem(icon: '🚨', label: 'Závažná nehoda — motorka nepojízdná',
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.accidentMajor, 'Závažná nehoda'); }),
              _PickerItem(icon: '🔐', label: 'Krádež motorky',
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.theft, 'Krádež motorky'); }),
            ],
          ),
        ),
      ),
    );
  }

  void _showBreakdownPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Typ poruchy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _PickerItem(icon: '🔩', label: 'Drobná závada — pokračuji v jízdě',
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.breakdownMinor, 'Drobná závada'); }),
              _PickerItem(icon: '🚫', label: 'Motorka nepojízdná',
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.breakdownMajor, 'Motorka nepojízdná'); }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref, String type, String desc) async {
    showMotoGoToast(context, icon: '⚠️', title: 'Hlásím incident...', message: 'Odesílám na centrálu');

    // Capture photo first
    final photos = await _capturePhotos(context);

    final incId = await createSosIncident(type: type, description: desc);
    if (incId == null) {
      if (context.mounted) showMotoGoToast(context, icon: '✗', title: 'Chyba', message: 'Nepodařilo se vytvořit incident');
      return;
    }

    // Upload photos
    if (photos.isNotEmpty) {
      await uploadSosPhotos(incId, photos);
    }

    if (!context.mounted) return;
    ref.invalidate(activeSosProvider);

    // Navigate based on type
    if (type == SosType.accidentMajor || type == SosType.breakdownMajor) {
      context.push(Routes.sosReplacement);
    } else {
      showMotoGoToast(context, icon: '✅', title: 'Incident nahlášen', message: 'MotoGo24 byla informována');
      context.push(Routes.sosDone);
    }
  }

  Future<List<XFile>> _capturePhotos(BuildContext context) async {
    final picker = ImagePicker();
    final photos = <XFile>[];
    try {
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2048);
      if (photo != null) photos.add(photo);
    } catch (_) {}
    return photos;
  }

  Future<void> _shareLocation(BuildContext context, WidgetRef ref) async {
    showMotoGoToast(context, icon: '📍', title: 'Zjišťuji polohu...', message: '');
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null) {
      await shareLocation(active.id);
      if (context.mounted) showMotoGoToast(context, icon: '📍', title: 'Poloha sdílena', message: 'MotoGo24 obdržela vaši pozici');
    } else {
      final incId = await createSosIncident(type: SosType.locationShare, description: 'Sdílení polohy');
      if (incId != null) await shareLocation(incId);
      if (context.mounted) showMotoGoToast(context, icon: '📍', title: 'Poloha sdílena', message: '');
    }
  }
}

class _ActiveBanner extends StatelessWidget {
  final SosIncident incident;
  const _ActiveBanner({required this.incident});

  @override
  Widget build(BuildContext context) {
    final statusLabels = {'reported': 'Nahlášeno', 'acknowledged': 'Přijato', 'in_progress': 'Řeší se'};
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: const Color(0xFFFDE68A), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠️ Aktivní SOS incident', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
          Text('Stav: ${statusLabels[incident.status] ?? incident.status} · ${incident.id.substring(incident.id.length - 8).toUpperCase()}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
        ],
      ),
    );
  }
}

class _SosOption extends StatelessWidget {
  final String icon; final String title; final String subtitle;
  final Color color; final VoidCallback onTap;
  const _SosOption({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm), border: Border.all(color: MotoGoColors.g200)),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 20)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
          ])),
          const Text('›', style: TextStyle(fontSize: 18, color: MotoGoColors.g400)),
        ]),
      ),
    );
  }
}

class _PickerItem extends StatelessWidget {
  final String icon; final String label; final VoidCallback onTap;
  const _PickerItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm), border: Border.all(color: MotoGoColors.g200)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)), const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black))),
          const Text('›', style: TextStyle(fontSize: 16, color: MotoGoColors.g400)),
        ]),
      ),
    );
  }
}
