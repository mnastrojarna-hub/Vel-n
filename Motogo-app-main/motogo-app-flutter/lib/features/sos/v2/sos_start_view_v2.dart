import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../sos_provider.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// v2 SOS start (SOS board "Start · výběr problému"): dark header without
/// aura, then in the OLD screen's order (owner 2026-11-07 "jen upgrade
/// vzhledu"): active incident (T3 amber) / status error, the AI service
/// agent, the emergency numbers 112 / 155 / 158, the problem rows; nonstop
/// dock. Same actions as before.
class SosStartViewV2 extends ConsumerWidget {
  final AsyncValue<SosIncident?> active;
  final Widget? statusError;
  final VoidCallback onBack;
  final VoidCallback onAccident;
  final VoidCallback onBreakdown;
  final VoidCallback onShareLocation;
  final VoidCallback onAi;
  final VoidCallback onOpenIncident;
  final void Function(String number) onDial;
  const SosStartViewV2({
    super.key,
    required this.active,
    this.statusError,
    required this.onBack,
    required this.onAccident,
    required this.onBreakdown,
    required this.onShareLocation,
    required this.onAi,
    required this.onOpenIncident,
    required this.onDial,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final inc = active.valueOrNull;
    return SosPageV2(
      onBack: onBack,
      header: SosHeaderV2(
        onBack: onBack,
        icon: MgIcons.alert,
        tint: SosTint.red,
        title: tr.sosTitle,
        sub: tr.tr('v2UxAsmSosPick'),
      ),
      sections: [
        if (inc != null && inc.isActive) SosActiveBannerV2(incident: inc, onTap: onOpenIncident),
        if (statusError != null) statusError!,
        _AiCard(onTap: onAi),
        _Emergency(onDial: onDial),
        SosRowV2(
          icon: MgIcons.crash,
          tint: SosTint.red,
          title: tr.tr('accidentTheft'),
          sub: tr.tr('reportAccidentTheft'),
          onTap: onAccident,
        ),
        SosRowV2(
          icon: MgIcons.wrench,
          tint: SosTint.amber,
          title: tr.tr('breakdownOnRoad'),
          sub: tr.tr('motoNotWorking'),
          onTap: onBreakdown,
        ),
        SosRowV2(
          icon: MgIcons.pin,
          tint: SosTint.ok,
          title: tr.shareLocation,
          sub: tr.tr('sendGpsToMotoGo'),
          onTap: onShareLocation,
        ),
      ],
    );
  }
}

/// "Aktivní SOS incident" T3 amber banner → incident detail.
class SosActiveBannerV2 extends StatelessWidget {
  final SosIncident incident;
  final VoidCallback onTap;
  const SosActiveBannerV2({super.key, required this.incident, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final status = switch (incident.status) {
      'reported' => tr.tr('reported'),
      'acknowledged' => tr.tr('accepted'),
      'in_progress' => tr.tr('inProgress'),
      _ => incident.status,
    };
    final id = incident.id.substring(incident.id.length - 8).toUpperCase();
    return Semantics(
      button: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MgColors.warnBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.warnBorder, width: 1.5),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Color(0xFFFFE2A8), shape: BoxShape.circle),
              child: const Center(child: MgIcon(MgIcons.alert, size: 20, color: MgColors.warn)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('activeSosIncident'), style: MgType.title.copyWith(fontSize: 14, color: MgColors.warn)),
                const SizedBox(height: 2),
                Text('${tr.tr('statusLabel')}: $status · $id', style: MgType.small.copyWith(color: MgColors.ink)),
                Text(tr.tr('v2UxAsmTapDetail'), style: MgType.micro.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: MgColors.warn)),
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.warn),
          ]),
        ),
      ),
    );
  }
}

class _Emergency extends StatelessWidget {
  final void Function(String number) onDial;
  const _Emergency({required this.onDial});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget tile(String n, String label) => Expanded(
          child: Semantics(
            button: true,
            label: '$n, $label',
            excludeSemantics: true,
            child: MgPress(
              onTap: () => onDial(n),
              child: Container(
                constraints: const BoxConstraints(minHeight: 96),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MgColors.sos, MgColors.err]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: MgColors.sos.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)],
                ),
                child: Stack(children: [
                  Positioned(top: 8, right: 8, child: MgIcon(MgIcons.phone, size: 14, color: MgColors.white(0.85))),
                  Align(
                    child: Padding(
                      // Below the phone glyph (top-right), never under it.
                      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(n, style: MgType.tab(MgType.display.copyWith(fontSize: 30, color: MgColors.onDark))),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label,
                              maxLines: 1, style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.white(0.92))),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
    return SosCardV2(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const MgIcon(MgIcons.alert, size: 18, color: MgColors.err),
          const SizedBox(width: 8),
          Expanded(child: Text(tr.tr('v2UxAsmSosCallFirst'), style: MgType.title.copyWith(fontSize: 14, color: MgColors.err))),
        ]),
        const SizedBox(height: 10),
        IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile('112', tr.tr('emergencyGeneral')),
          const SizedBox(width: 8),
          tile('155', tr.tr('emergencyAmbulance')),
          const SizedBox(width: 8),
          tile('158', tr.tr('emergencyPolice')),
        ])),
      ]),
    );
  }
}

class _AiCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AiCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      child: MgPress(
        onTap: onTap,
        child: MgDarkHero(
          rankAura: false,
          radius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MgColors.neon, width: 2)),
              child: const Center(child: MgIcon(MgIcons.chat, size: 20, color: MgColors.neon)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('aiServiceAgent'), style: MgType.title.copyWith(color: MgColors.onDark)),
                Text(tr.tr('aiServiceAgentDesc'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.neon),
          ]),
        ),
      ),
    );
  }
}
