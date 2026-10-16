import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_feedback.dart';
import 'sos_location.dart';
import 'sos_provider.dart';
import '../../core/widgets/mg_nav_controls.dart';

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
  bool _sentWithoutLocation = false;

  /// Creates or re-uses an active SOS incident. Throws on error.
  Future<String> _ensureIncident() async {
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null && active.isActive) return active.id;

    final description = t(context).tr('accidentMajorTitle');
    // Poloha max 20 s a bez vytahování do Nastavení; bez ní hlášení odejde
    // stejně a zákazník se dozví, že má polohu říct po telefonu.
    final loc = await sosLocate();
    final lat = loc.pos?.latitude, lng = loc.pos?.longitude;
    _sentWithoutLocation = loc.pos == null;

    return createSosIncident(
      type: SosType.accidentMajor,
      description: description,
      lat: lat, lng: lng,
      isFault: _fault,
    );
  }

  Future<void> _requestReplacement() async {
    if (_fault == null || _submitting) return;
    setState(() => _submitting = true);

    try {
      await _ensureIncident();
      ref.invalidate(activeSosProvider);
      if (mounted) context.push(Routes.sosReplacement);
      if (mounted && _sentWithoutLocation) showSosSentWithoutLocation(context);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      if (!mounted) return;
      final retry = await showSosActionFailed(context,
          title: t(context).tr('eoSosReportFailTitle'), error: e);
      if (retry && mounted) await _requestReplacement();
      return;
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _endRide() async {
    if (_fault == null || _submitting) return;
    setState(() => _submitting = true);

    // Odtah se hlásí jako objednaný JEN když se žádost opravdu uložila —
    // jinak důvod + volání (odtah zařídíme po telefonu) / Zkusit znovu.
    try {
      final incId = await _ensureIncident();
      await sosEndRide(incId, isFault: _fault!);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      if (!mounted) return;
      final retry = await showSosActionFailed(context,
          title: t(context).tr('eoSosTowFailTitle'),
          error: e,
          extra: t(context).tr('eoSosTowByPhone'));
      if (retry && mounted) await _endRide();
      return;
    }
    ref.invalidate(activeSosProvider);

    if (mounted) {
      ref.read(sosDoneTypeProvider.notifier).state =
          _fault! ? SosDoneType.towOrdered : SosDoneType.towFree;
      showMotoGoToast(context, icon: '✅', title: t(context).tr('towOrdered'), message: t(context).tr('towOrderedMsg'));
      if (_sentWithoutLocation) showSosSentWithoutLocation(context);
      context.go(Routes.sosDone);
    }
    if (mounted) setState(() => _submitting = false);
  }

  /// Úspěch jen když poloha opravdu dorazila (dřív vždy „Poloha sdílena",
  /// i bez aktivního incidentu, oprávnění nebo internetu).
  Future<void> _shareLocation() async {
    final progress = SosProgress.show(context, t(context).tr('sharingLocation'));
    final active = ref.read(activeSosProvider).valueOrNull;
    final r = await shareLocationNow(active?.isActive == true ? active!.id : null);
    progress.close();
    if (!mounted) return;
    ref.invalidate(activeSosProvider);
    final retry = await showSosLocationResult(context, r);
    if (retry && mounted) await _shareLocation();
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
              const SizedBox(height: 16),

              // Action cards (only after fault decision). Náhradní motorka je
              // v aplikaci VŽDY ZDARMA — placené flow (spoluúčast 30 000 Kč)
              // bylo zrušeno; zůstává jen náhrada zdarma nebo odtah.
              if (_fault != null) ...[
                _actionCard(
                  icon: '🏍️',
                  title: t(context).tr('replacementFree'),
                  subtitle: t(context).tr('selectMotoAndAddress'),
                  color: MotoGoColors.greenPale,
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
        MgBackTap(
          onTap: () => context.backOr(Routes.sos),
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
