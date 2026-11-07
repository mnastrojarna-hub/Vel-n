import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// v2 SOS "Hotovo" (SOS board ×8): plain dark success hero (neon ✓ /
/// truck / bike disc 88, one-shot; NO rank aura — SOS is never rank) with
/// "SOS INCIDENT · #ID", white cards (incident number, CO BUDE DÁL?), the
/// existing actions, nonstop dock (assistance line). Texts = the old
/// screen's per-type config.
class SosDoneViewV2 extends StatelessWidget {
  final String title;
  final String subtitle;
  final String nextSteps;
  final String? icon;
  final String? refLabel;
  final VoidCallback onBack;
  final VoidCallback onReservations;
  final VoidCallback onMessages;
  final VoidCallback onHome;
  const SosDoneViewV2({
    super.key,
    required this.title,
    required this.subtitle,
    required this.nextSteps,
    this.icon,
    required this.refLabel,
    required this.onBack,
    required this.onReservations,
    required this.onMessages,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return SosPageV2(
      onBack: onBack,
      dock: SosDockV2(callEyebrow: tr.tr('assistanceLine')),
      header: SosHeaderV2(
        onBack: onBack,
        center: MgToneDisc(tone: MgTone.ok, size: 88, dark: true, icon: icon),
        eyebrow: refLabel == null ? 'SOS' : 'SOS INCIDENT · $refLabel',
        title: title,
        sub: subtitle,
      ),
      sections: [
        if (refLabel != null)
          SosCardV2(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: MgColors.panel, borderRadius: BorderRadius.circular(14)),
                child: const Center(child: MgIcon(MgIcons.idCard, size: 22, color: MgColors.neon)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr.tr('sosRefNumber').toUpperCase(),
                      style: MgType.meta.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MgColors.link)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(refLabel!,
                        style: MgType.tab(MgType.h1.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
                  ),
                  const SizedBox(height: 4),
                  Text(tr.tr('v2UxAsmRefKeep'), style: MgType.small.copyWith(color: MgColors.meta)),
                ]),
              ),
            ]),
          ),
        SosCardV2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr.tr('whatHappensNext').toUpperCase(),
                style: MgType.meta.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MgColors.link)),
            const SizedBox(height: 8),
            Text(nextSteps, style: MgType.body.copyWith(color: MgColors.ink)),
          ]),
        ),
        const SizedBox(height: 4),
        MgBtnInk(label: tr.tr('myReservations').toUpperCase(), icon: MgIcons.list, onTap: onReservations),
        MgBtnGhostLight(label: tr.tr('messagesFromMotoGo'), icon: MgIcons.chat, onTap: onMessages),
        Center(child: MgBtnText(label: tr.tr('backToHome'), onTap: onHome)),
      ],
    );
  }
}
