import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/native/gps_service.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_provider.dart';

/// "Motorka nepojízdná" screen for accidents — mirrors s-sos-nepojizda.
/// Shows fault decision (zaviněná/nezaviněná) + action cards.
class SosImmobileScreen extends ConsumerStatefulWidget {
  const SosImmobileScreen({super.key});

  @override
  ConsumerState<SosImmobileScreen> createState() => _SosImmobileState();
}

class _SosImmobileState extends ConsumerState<SosImmobileScreen> {
  bool? _fault; // null = not selected, true = at-fault, false = not-at-fault
  bool _submitting = false;

  /// Creates or re-uses an active SOS incident. Throws on error.
  Future<String> _ensureIncident() async {
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null && active.isActive) return active.id;

    double? lat, lng;
    try {
      final pos = await GpsService.getCurrentPosition();
      lat = pos?.latitude;
      lng = pos?.longitude;
    } catch (_) {}

    return createSosIncident(
      type: SosType.accidentMajor,
      description: t(context).tr('accidentMajorTitle'),
      lat: lat, lng: lng,
      isFault: _fault,
    );
  }

  Future<void> _requestReplacement() async {
    if (_fault == null || _submitting) return;
    setState(() => _submitting = true);

    try {
      final incId = await _ensureIncident();
      ref.read(sosFaultProvider.notifier).state = _fault;
      ref.invalidate(activeSosProvider);
      if (mounted) context.push(Routes.sosReplacement);
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
    }
    setState(() => _submitting = false);
  }

  Future<void> _endRide() async {
    if (_fault == null || _submitting) return;
    setState(() => _submitting = true);

    String incId;
    try {
      incId = await _ensureIncident();
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
      setState(() => _submitting = false);
      return;
    }

    await sosEndRide(incId, isFault: _fault!);
    ref.invalidate(activeSosProvider);

    if (mounted) {
      ref.read(sosDoneTypeProvider.notifier).state =
          _fault! ? SosDoneType.towOrdered : SosDoneType.towFree;
      showMotoGoToast(context, icon: '✅', title: t(context).tr('towOrdered'), message: t(context).tr('towOrderedMsg'));
      context.go(Routes.sosDone);
    }
    setState(() => _submitting = false);
  }

  Future<void> _shareLocation() async {
    showMotoGoToast(context, icon: '📍', title: t(context).tr('sharingLocation'), message: '');
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null) {
      await shareLocation(active.id);
    }
    if (mounted) showMotoGoToast(context, icon: '📍', title: t(context).tr('locationShared'), message: t(context).tr('locationSharedMsg'));
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
              _header(context),
              const SizedBox(height: 12),

              // Step-by-step guide for accident
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MotoGoColors.amberBg,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.amberBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📋 ${t(context).tr('accidentStepsTitle')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF92400E))),
                    const SizedBox(height: 8),
                    Text(t(context).tr('accidentSteps'), style: const TextStyle(fontSize: 11, color: Color(0xFF78350F), height: 1.6)),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Fault decision buttons
              _faultDecision(),
              const SizedBox(height: 12),

              // Dynamic info banner
              if (_fault != null) _infoBanner(),
              if (_fault != null) const SizedBox(height: 16),

              // Action cards (only after fault decision)
              if (_fault != null) ...[
                _actionCard(
                  icon: '🏍️',
                  title: _fault! ? t(context).tr('replacementPaid') : t(context).tr('replacementFree'),
                  subtitle: _fault!
                      ? t(context).tr('replacementPaidDesc')
                      : t(context).tr('replacementFreeDesc'),
                  color: _fault! ? MotoGoColors.redBg : MotoGoColors.greenPale,
                  onTap: _requestReplacement,
                ),
                const SizedBox(height: 8),
                _actionCard(
                  icon: '🚛',
                  title: t(context).tr('endRideTow'),
                  subtitle: t(context).tr('endRideTowDesc'),
                  color: const Color(0xFFF3F4F6),
                  onTap: _endRide,
                ),
              ],

              const SizedBox(height: 20),

              // Share location section
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
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _shareLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MotoGoColors.green,
                        foregroundColor: MotoGoColors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      ),
                      child: Text('📍 ${t(context).tr('shareGps')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
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

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MotoGoColors.redBg,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Text('🚫', style: TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t(context).tr('motoImmobile'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          Text(t(context).tr('cannotContinueRide'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
        ])),
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
          ),
        ),
      ]),
    );
  }

  Widget _faultDecision() {
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: () => setState(() => _fault = false),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: _fault == false ? MotoGoColors.greenPale : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
            border: Border.all(
              color: _fault == false ? MotoGoColors.greenDark : MotoGoColors.g200,
              width: _fault == false ? 2 : 1,
            ),
          ),
          child: Column(children: [
            Text('✅', style: TextStyle(fontSize: 20, color: _fault == false ? MotoGoColors.greenDark : MotoGoColors.g400)),
            const SizedBox(height: 4),
            Text(t(context).tr('notMyFault'), textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: _fault == false ? MotoGoColors.greenDark : MotoGoColors.g600)),
          ]),
        ),
      )),
      const SizedBox(width: 8),
      Expanded(child: GestureDetector(
        onTap: () => setState(() => _fault = true),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: _fault == true ? MotoGoColors.redBg : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
            border: Border.all(
              color: _fault == true ? MotoGoColors.red : MotoGoColors.g200,
              width: _fault == true ? 2 : 1,
            ),
          ),
          child: Column(children: [
            Text('⚠️', style: TextStyle(fontSize: 20, color: _fault == true ? MotoGoColors.red : MotoGoColors.g400)),
            const SizedBox(height: 4),
            Text(t(context).tr('myFault'), textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: _fault == true ? MotoGoColors.red : MotoGoColors.g600)),
          ]),
        ),
      )),
    ]);
  }

  Widget _infoBanner() {
    final isGreen = _fault == false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isGreen ? MotoGoColors.greenPale : MotoGoColors.redBg,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
      ),
      child: Text(
        isGreen
            ? '💚 ${t(context).tr('breakdownFreeInfo')}'
            : '⚠️ ${t(context).tr('faultPaidInfo')}',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: isGreen ? MotoGoColors.greenDarker : const Color(0xFF991B1B)),
      ),
    );
  }

  Widget _actionCard({
    required String icon, required String title, required String subtitle,
    required Color color, required VoidCallback onTap,
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
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: MotoGoColors.g600)),
          ])),
          const Text('›', style: TextStyle(fontSize: 18, color: MotoGoColors.g400)),
        ]),
      ),
    );
  }
}
