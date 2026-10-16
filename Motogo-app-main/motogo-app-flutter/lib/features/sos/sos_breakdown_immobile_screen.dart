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
  bool _sentWithoutLocation = false;
  final _descCtrl = TextEditingController();

  /// Creates or re-uses an active SOS incident. Throws on error.
  Future<String> _ensureIncident() async {
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null && active.isActive) return active.id;

    // Poloha max 20 s a bez vytahování do Nastavení; bez ní hlášení odejde
    // stejně a zákazník se dozví, že má polohu říct po telefonu.
    final loc = await sosLocate();
    final lat = loc.pos?.latitude, lng = loc.pos?.longitude;
    _sentWithoutLocation = loc.pos == null;

    return createSosIncident(
      type: SosType.breakdownMajor,
      description: _descCtrl.text.trim().isNotEmpty
          ? _descCtrl.text.trim()
          : 'Porucha — motorka nepojízdná',
      lat: lat,
      lng: lng,
      isFault: false,
    );
  }

  Future<void> _requestReplacement() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await _ensureIncident();
      // Breakdown = always free (fault = null → free)
      ref.read(sosFaultProvider.notifier).state = null;
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

  Future<void> _endRideFree() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    // Odtah se hlásí jako objednaný JEN když se žádost opravdu uložila —
    // jinak důvod + volání (odtah zařídíme po telefonu) / Zkusit znovu.
    try {
      final incId = await _ensureIncident();
      await sosEndRide(incId, isFault: false);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      if (!mounted) return;
      final retry = await showSosActionFailed(context,
          title: t(context).tr('eoSosTowFailTitle'),
          error: e,
          extra: t(context).tr('eoSosTowByPhone'));
      if (retry && mounted) await _endRideFree();
      return;
    }
    ref.invalidate(activeSosProvider);

    if (mounted) {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.towFree;
      showMotoGoToast(context,
          icon: '✅',
          title: t(context).tr('rentalFreeReturn'),
          message: t(context).tr('fullRefundTow'));
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
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
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
                  MgBackTap(
                    onTap: () => context.backOr(Routes.sos),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: MotoGoColors.green,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Center(
                          child: Text('←',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
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
              const SizedBox(height: 12),

              // Problem description
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.g200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context).tr('breakdownDescLabel'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: t(context).tr('breakdownDescHint'),
                        hintStyle: const TextStyle(fontSize: 12, color: MotoGoColors.g400),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

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
