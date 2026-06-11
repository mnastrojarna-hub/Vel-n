import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/native/gps_service.dart';
import '../../core/i18n/i18n_provider.dart';
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
                      child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🆘 ${t(context).sosTitle}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                      Text(t(context).tr('selectProblemType'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
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
                  child: Row(
                    children: [
                      const Text('🤖', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t(context).tr('aiServiceAgent'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text(t(context).tr('aiServiceAgentDesc'), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      )),
                      const Text('›', style: TextStyle(fontSize: 20, color: MotoGoColors.green)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Emergency numbers banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MotoGoColors.redBg,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🚨 ${t(context).tr('emergencyFirst')}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: MotoGoColors.red),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _EmergencyChip(label: '112', desc: t(context).tr('emergencyGeneral')),
                        const SizedBox(width: 8),
                        _EmergencyChip(label: '155', desc: t(context).tr('emergencyAmbulance')),
                        const SizedBox(width: 8),
                        _EmergencyChip(label: '158', desc: t(context).tr('emergencyPolice')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Incident types
              _SosOption(
                icon: '💥', title: t(context).tr('accidentTheft'),
                subtitle: t(context).tr('reportAccidentTheft'),
                color: MotoGoColors.redBg,
                onTap: () => _showAccidentPicker(context, ref),
              ),
              const SizedBox(height: 8),
              _SosOption(
                icon: '🔧', title: t(context).tr('breakdownOnRoad'),
                subtitle: t(context).tr('motoNotWorking'),
                color: MotoGoColors.amberBg,
                onTap: () => _showBreakdownPicker(context, ref),
              ),
              const SizedBox(height: 8),
              _SosOption(
                icon: '📍', title: t(context).shareLocation,
                subtitle: t(context).tr('sendGpsToMotoGo'),
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
                child: Row(
                  children: [
                    const Text('📞', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(context).tr('nonstopLine'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                        const Text('+420 774 256 271', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
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
              Text(t(context).tr('accidentType'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _PickerItem(icon: '🎯', label: t(context).tr('minorAccidentContinue'),
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.accidentMinor, t(context).tr('accidentMinorLabel')); }),
              _PickerItem(icon: '🚨', label: t(context).tr('seriousAccidentImmobile'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosAccident); }),
              _PickerItem(icon: '🔐', label: t(context).tr('theftTitle'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosTheft); }),
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
              Text(t(context).tr('breakdownType'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _PickerItem(icon: '🔩', label: t(context).tr('minorDefectContinue'),
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.breakdownMinor, t(context).tr('breakdownMinorLabel')); }),
              _PickerItem(icon: '🚫', label: t(context).tr('motoImmobile'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosBreakdown); }),
              _PickerItem(icon: '🔧', label: t(context).tr('nearestServiceInvoice'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosService); }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref, String type, String desc) async {
    // 0. Confirm before creating incident
    final confirmed = await _confirmReport(context, desc);
    if (!confirmed || !context.mounted) return;

    showMotoGoToast(context, icon: '⚠️', title: t(context).tr('reportingIncident'), message: t(context).tr('sendingToCentral'));

    // 1. Capture GPS position
    double? lat, lng;
    try {
      final pos = await GpsService.getCurrentPosition();
      lat = pos?.latitude;
      lng = pos?.longitude;
    } catch (_) {}

    // 2. Determine fault (major accident = ask, breakdown = not at fault)
    final bool isFault = type == SosType.accidentMajor || type == SosType.theft;

    // 3. Create incident via direct INSERT with GPS
    String incId;
    try {
      incId = await createSosIncident(
        type: type,
        description: desc,
        lat: lat,
        lng: lng,
        isFault: isFault,
      );
    } catch (e) {
      if (context.mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
      return;
    }

    // 4. Ask user if they want to add photos (optional)
    if (context.mounted) {
      final wantsPhoto = await _askForPhoto(context);
      if (wantsPhoto && context.mounted) {
        try {
          final photos = await _capturePhotos(context);
          if (photos.isNotEmpty) {
            await uploadSosPhotos(incId, photos);
          }
        } catch (_) {
          if (context.mounted) {
            showMotoGoToast(context, icon: '⚠️', title: t(context).tr('photoUploadFailed'), message: t(context).tr('incidentCreatedNoPhoto'));
          }
        }
      }
    }

    if (!context.mounted) return;
    ref.invalidate(activeSosProvider);

    // 5. Set done type based on incident type
    if (type == SosType.accidentMinor) {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.accidentMinor;
    } else if (type == SosType.breakdownMinor) {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.breakdownMinor;
    } else {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.generic;
    }

    showMotoGoToast(context, icon: '✅', title: t(context).tr('incidentReported'), message: t(context).tr('motoGoInformed'));
    context.push(Routes.sosDone);
  }

  Future<bool> _confirmReport(BuildContext context, String desc) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('⚠️ ${t(context).confirm}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
              const SizedBox(height: 8),
              Text('${t(context).tr('confirmReportQuestion')} „$desc"?', style: const TextStyle(fontSize: 13, color: MotoGoColors.g400)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MotoGoColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: Text(t(context).tr('yesReport'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    foregroundColor: MotoGoColors.g400,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(t(context).cancel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  Future<bool> _askForPhoto(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('📷 ${t(context).tr('photoDocumentation')}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
              const SizedBox(height: 8),
              Text(t(context).tr('wantToAddPhoto'), style: const TextStyle(fontSize: 13, color: MotoGoColors.g400)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MotoGoColors.green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: Text('📸 ${t(context).tr('takePhoto')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    foregroundColor: MotoGoColors.g400,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(t(context).tr('skip'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  Future<List<XFile>> _capturePhotos(BuildContext context) async {
    final picker = ImagePicker();
    final photos = <XFile>[];
    try {
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2048);
      if (photo != null) photos.add(photo);
    } catch (e) {
      if (context.mounted) {
        showMotoGoToast(context, icon: '⚠️', title: t(context).tr('photoCaptureFailed'), message: t(context).tr('tryAgainOrSkip'));
      }
    }
    return photos;
  }

  Future<void> _shareLocation(BuildContext context, WidgetRef ref) async {
    showMotoGoToast(context, icon: '📍', title: t(context).tr('sharingLocation'), message: '');
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null) {
      await shareLocation(active.id);
      if (context.mounted) showMotoGoToast(context, icon: '📍', title: t(context).tr('locationShared'), message: t(context).tr('locationSharedMsg'));
    } else {
      // Get GPS before creating incident so coords are attached from start
      double? lat, lng;
      try {
        final pos = await GpsService.getCurrentPosition();
        lat = pos?.latitude;
        lng = pos?.longitude;
      } catch (_) {}
      try {
        final incId = await createSosIncident(type: SosType.locationShare, description: 'Sdílení polohy', lat: lat, lng: lng);
        await shareLocation(incId);
      } catch (_) {}
      if (context.mounted) showMotoGoToast(context, icon: '📍', title: t(context).tr('locationShared'), message: '');
    }
  }
}

class _ActiveBanner extends StatelessWidget {
  final SosIncident incident;
  const _ActiveBanner({required this.incident});

  @override
  Widget build(BuildContext context) {
    final statusLabels = {'reported': t(context).tr('reported'), 'acknowledged': t(context).tr('accepted'), 'in_progress': t(context).tr('inProgress')};
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MotoGoColors.amberBg, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.amberBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠️ ${t(context).tr('activeSosIncident')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
          Text('${t(context).tr('statusLabel')}: ${statusLabels[incident.status] ?? incident.status} · ${incident.id.substring(incident.id.length - 8).toUpperCase()}',
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

class _EmergencyChip extends StatelessWidget {
  final String label;
  final String desc;
  const _EmergencyChip({required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse('tel:$label')),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.red)),
              Text(desc, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
            ],
          ),
        ),
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
