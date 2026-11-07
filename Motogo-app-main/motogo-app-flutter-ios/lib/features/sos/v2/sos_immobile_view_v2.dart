import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import 'sos_actions_v2.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// Remembers which existing action the customer tapped, so only THAT one
/// shows the spinner while the screen's own `_submitting` runs.
mixin SosPendingMixin<T extends StatefulWidget> on State<T> {
  String? _tapped;

  String? pendingOf(bool submitting) => submitting ? _tapped : null;

  VoidCallback tapped(String id, VoidCallback action) => () {
        setState(() => _tapped = id);
        action();
      };
}

/// v2 "Vážná nehoda · nepojízdná" (SOS board): dark guide card from the
/// accident steps, ZAVINĚNÍ choice cards (hint until chosen), the actions
/// revealed below once chosen (same condition), share location.
class SosImmobileViewV2 extends StatefulWidget {
  final bool? fault;
  final bool submitting;
  final ValueChanged<bool> onFault;
  final VoidCallback onBack;
  final VoidCallback onReplacement;
  final VoidCallback onTow;
  final VoidCallback onShare;
  const SosImmobileViewV2({
    super.key,
    required this.fault,
    required this.submitting,
    required this.onFault,
    required this.onBack,
    required this.onReplacement,
    required this.onTow,
    required this.onShare,
  });

  @override
  State<SosImmobileViewV2> createState() => _SosImmobileViewV2State();
}

class _SosImmobileViewV2State extends State<SosImmobileViewV2> with SosPendingMixin {
  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final steps = sosSteps(tr.tr('v2UxAsmAccidentSteps'));
    return SosPageV2(
      onBack: widget.onBack,
      header: SosHeaderV2(
        onBack: widget.onBack,
        icon: MgIcons.ban,
        tint: SosTint.red,
        eyebrow: tr.tr('accidentMajorLabel'),
        title: tr.tr('motoImmobile'),
        sub: tr.tr('cannotContinueRide'),
      ),
      sections: [
        SosGuideV2(title: tr.tr('accidentStepsTitle'), steps: [for (final s in steps) SosStepV2(s)]),
        const SizedBox(height: 4),
        SosChoicePairV2(
          eyebrow: tr.tr('faultLabel'),
          value: widget.fault == null ? null : !widget.fault!,
          onChanged: (notMine) => widget.onFault(!notMine),
          a: (true, MgIcons.shield, tr.tr('notMyFault').replaceAll('\n', ' '), null),
          b: (false, MgIcons.warn, tr.tr('myFault').replaceAll('\n', ' '), null),
          hint: tr.tr('v2UxAsmFaultHint'),
        ),
        MgAnimatedSize(
          duration: MgMotion.of(context, MgMotion.sticky),
          curve: MgMotion.emphasized,
          alignment: Alignment.topCenter,
          child: widget.fault == null
              ? const SizedBox(width: double.infinity)
              : SosReplaceTowV2(
                  pending: pendingOf(widget.submitting),
                  caption: tr.tr('v2UxAsmPickBikeAddress'),
                  onReplacement: tapped('repl', widget.onReplacement),
                  onTow: tapped('tow', widget.onTow),
                ),
        ),
        SosShareCardV2(onShare: widget.onShare),
      ],
    );
  }
}

/// v2 "Porucha · nepojízdná" (SOS board): free-replacement note, the
/// description card (same controller), replacement + tow, share location.
class SosBreakdownViewV2 extends StatefulWidget {
  final TextEditingController descCtrl;
  final bool submitting;
  final VoidCallback onBack;
  final VoidCallback onReplacement;
  final VoidCallback onTow;
  final VoidCallback onShare;
  const SosBreakdownViewV2({
    super.key,
    required this.descCtrl,
    required this.submitting,
    required this.onBack,
    required this.onReplacement,
    required this.onTow,
    required this.onShare,
  });

  @override
  State<SosBreakdownViewV2> createState() => _SosBreakdownViewV2State();
}

class _SosBreakdownViewV2State extends State<SosBreakdownViewV2> with SosPendingMixin {
  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return SosPageV2(
      onBack: widget.onBack,
      header: SosHeaderV2(
        onBack: widget.onBack,
        icon: MgIcons.wrench,
        tint: SosTint.amber,
        eyebrow: tr.tr('breakdownMajorLabel'),
        title: tr.tr('motoImmobile'),
        sub: tr.tr('breakdownImmobileTitle'),
      ),
      sections: [
        SosNoteV2(ok: true, icon: MgIcons.checkCircle, title: tr.tr('v2UxAsmBreakdownFree')),
        SosCardV2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr.tr('v2UxAsmDescribe'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
            const SizedBox(height: 8),
            TextField(
              controller: widget.descCtrl,
              maxLines: 3,
              style: MgType.body.copyWith(color: MgColors.ink),
              decoration: mgInputDecoration(context, hint: tr.tr('v2UxAsmDescribeHint')).copyWith(hintMaxLines: 3),
            ),
          ]),
        ),
        SosReplaceTowV2(
          pending: pendingOf(widget.submitting),
          caption: tr.tr('v2UxAsmReplFreeCaption'),
          onReplacement: tapped('repl', widget.onReplacement),
          onTow: tapped('tow', widget.onTow),
        ),
        SosShareCardV2(onShare: widget.onShare),
      ],
    );
  }
}
