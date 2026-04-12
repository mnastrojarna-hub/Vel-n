import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/native/gps_service.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_provider.dart';

/// "Nepojízdná – porucha" screen — mirrors s-sos-nepojizda-porucha.
/// Always free (breakdown = not customer fault).
/// Two options: replacement (free) or end ride (free refund).
class SosBreakdownImmobileScreen extends ConsumerStatefulWidget {
  const SosBreakdownImmobileScreen({super.key});

  @override
  ConsumerState<SosBreakdownImmobileScreen> createState() =>
      _SosBreakdownImmobileState();
}

class _SosBreakdownImmobileState
    extends ConsumerState<SosBreakdownImmobileScreen> {
  bool _submitting = false;

  Future<String?> _ensureIncident() async {
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null && active.isActive) return active.id;

    double? lat, lng;
    try {
      final pos = await GpsService.getCurrentPosition();
      lat = pos?.latitude;
      lng = pos?.longitude;
    } catch (_) {}

    return createSosIncident(
      type: SosType.breakdownMajor,
      description: 'Porucha — motorka nepojízdná',
      lat: lat,
      lng: lng,
      isFault: false,
    );
  }

  Future<void> _requestReplacement() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final incId = await _ensureIncident();
    if (incId == null) {
      if (mounted) {
        showMotoGoToast(context,
            icon: '✗', title: t(context).error, message: t(context).tr('incidentCreateFailed'));
      }
      setState(() => _submitting = false);
      return;
    }

    // Breakdown = always free (fault = null → free)
    ref.read(sosFaultProvider.notifier).state = null;
    ref.invalidate(activeSosProvider);

    if (mounted) context.push(Routes.sosReplacement);
    setState(() => _submitting = false);
  }

  Future<void> _endRideFree() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final incId = await _ensureIncident();
    if (incId == null) {
      if (mounted) {
        showMotoGoToast(context,
            icon: '✗', title: t(context).error, message: t(context).tr('incidentCreateFailed'));
      }
      setState(() => _submitting = false);
      return;
    }

    await sosEndRide(incId, isFault: false);
    ref.invalidate(activeSosProvider);

    if (mounted) {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.towFree;
      showMotoGoToast(context,
          icon: '✅',
          title: t(context).tr('rentalFreeReturn'),
          message: t(context).tr('fullRefundTow'));
      context.go(Routes.sosDone);
    }
    setState(() => _submitting = false);
  }

  Future<void> _shareLocation() async {
    showMotoGoToast(context, icon: '📍', title: t(context).tr('sharingLocation'), message: '');
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null) await shareLocation(active.id);
    if (mounted) {
      showMotoGoToast(context,
          icon: '📍', title: t(context).tr('locationShared'), message: t(context).tr('locationSharedMsg'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MotoGoColors.amberBg,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  border: Border.all(color: MotoGoColors.amberBorder),
                ),
                child: Row(children: [
                  const Text('🔧', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(t(context).tr('motoImmobile'),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: MotoGoColors.black)),
                        Text(t(context).tr('breakdownImmobileTitle'),
                            style:
                                const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                      ])),
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Center(
                          child: Text('←',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w900))),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Green info banner — always free for breakdowns
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                ),
                child: Text(
                  '💚 ${t(context).tr('breakdownFreeInfo')}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MotoGoColors.greenDarker),
                ),
              ),
              const SizedBox(height: 16),

              // Option 1: Free replacement
              _actionCard(
                icon: '🏍️',
                title: t(context).tr('replacementFree'),
                subtitle: t(context).tr('replacementFreeDesc'),
                color: MotoGoColors.greenPale,
                onTap: _requestReplacement,
              ),
              const SizedBox(height: 8),

              // Option 2: End ride (free refund + tow)
              _actionCard(
                icon: '🚛',
                title: t(context).tr('endRideTow'),
                subtitle: t(context).tr('endRideTowDesc'),
                color: const Color(0xFFF3F4F6),
                onTap: _endRideFree,
              ),
              const SizedBox(height: 20),

              // Share location
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.g200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t(context).tr('shareLocationAssistants'),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: MotoGoColors.g400,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _shareLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MotoGoColors.green,
                        foregroundColor: MotoGoColors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50)),
                      ),
                      child: Text('📍 ${t(context).tr('shareGps')}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard({
    required String icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _submitting ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
          border: Border.all(color: MotoGoColors.g200),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: MotoGoColors.black)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: MotoGoColors.g600)),
              ])),
          const Text('›',
              style: TextStyle(fontSize: 18, color: MotoGoColors.g400)),
        ]),
      ),
    );
  }
}
