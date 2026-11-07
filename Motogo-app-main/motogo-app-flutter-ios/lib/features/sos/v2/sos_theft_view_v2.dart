import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import 'sos_actions_v2.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// v2 "Krádež" (SOS board): dark 3-step guide (step 1 = red "Volat Policii
/// ČR – 158", the existing tel:158), liability note, "secured?" choice
/// cards, red "Nahlásit incident" → ✓ state → "OBJEDNAT NÁHRADNÍ MOTORKU"
/// + "Nechci náhradu". Same state and actions as the old screen.
class SosTheftViewV2 extends StatelessWidget {
  final bool reported;
  final bool submitting;
  final bool? secured;
  final ValueChanged<bool> onSecured;
  final VoidCallback onBack;
  final VoidCallback onCallPolice;
  final VoidCallback onReport;
  final VoidCallback onReplacement;
  final VoidCallback onNoReplacement;
  const SosTheftViewV2({
    super.key,
    required this.reported,
    required this.submitting,
    required this.secured,
    required this.onSecured,
    required this.onBack,
    required this.onCallPolice,
    required this.onReport,
    required this.onReplacement,
    required this.onNoReplacement,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return SosPageV2(
      onBack: onBack,
      header: SosHeaderV2(
        onBack: onBack,
        icon: MgIcons.lock,
        tint: SosTint.red,
        eyebrow: tr.tr('v2UxAsmTheftEyebrow'),
        title: tr.tr('theftTitle'),
        sub: tr.tr('v2UxAsmReportNow'),
      ),
      sections: [
        SosGuideV2(steps: [
          SosStepV2(tr.tr('v2UxAsmTheft1T'),
              icon: MgIcons.phone,
              text: tr.tr('v2UxAsmTheft1D'),
              action: MgBtnSos(label: tr.tr('theftCallPolice'), onTap: onCallPolice)),
          SosStepV2(tr.tr('v2UxAsmTheft2T'), icon: MgIcons.chat, text: tr.tr('v2UxAsmTheft2D')),
          SosStepV2(tr.tr('v2UxAsmTheft3T'), icon: MgIcons.doc, text: tr.tr('v2UxAsmTheft3D')),
        ]),
        SosNoteV2(
          icon: MgIcons.scale,
          title: tr.tr('v2UxAsmTheftLiability'),
          lines: [(true, tr.tr('theftSecuredInfo')), (false, tr.tr('theftUnsecuredInfo'))],
        ),
        SosChoicePairV2(
          eyebrow: tr.tr('theftSecuredQuestion'),
          value: secured,
          onChanged: onSecured,
          a: (true, MgIcons.shield, tr.tr('theftYesSecured'), tr.tr('theftSecuredDesc')),
          b: (false, MgIcons.shieldX, tr.tr('theftNoUnsecured'), tr.tr('theftUnsecuredDesc')),
        ),
        if (submitting)
          const SosBusyButtonV2(red: true)
        else if (reported)
          Semantics(
            liveRegion: true,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: MgColors.tintOk,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: MgColors.tintOkBorder, width: 1.5),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const MgIcon(MgIcons.checkCircle, size: 20, color: MgColors.link),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('${tr.tr('theftReported')} MotoGo24',
                      textAlign: TextAlign.center, style: MgType.button.copyWith(color: MgColors.onTintOk)),
                ),
              ]),
            ),
          )
        else
          MgBtnSos(label: '${tr.tr('reportIncident')} MotoGo24', onTap: onReport),
        MgAnimatedSize(
          duration: MgMotion.of(context, MgMotion.sticky),
          curve: MgMotion.emphasized,
          alignment: Alignment.topCenter,
          child: !reported
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  const Divider(height: 1, thickness: 1, color: MgColors.line),
                  const SizedBox(height: 16),
                  Text(tr.tr('v2UxAsmWantReplacement'), style: MgType.title.copyWith(color: MgColors.ink)),
                  const SizedBox(height: 10),
                  MgBtnInk(
                    label: tr.tr('orderReplacementMoto').toUpperCase(),
                    icon: MgIcons.bike,
                    onTap: onReplacement,
                  ),
                  const SizedBox(height: 4),
                  Center(child: MgBtnText(label: tr.tr('noReplacementEnd'), onTap: onNoReplacement)),
                ]),
        ),
      ],
    );
  }
}
