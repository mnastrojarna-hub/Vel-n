import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_parts.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 look of `ResPickupProcedure` (self-service pickup steps). Today the
/// steps sit in a collapsed section; here the same steps open from a link
/// in CO TEĎ into a light sheet (V22 "Postup na pobočce"). The widget keeps
/// computing the steps (gate / locker / no gear) — this only draws them.
class ResProcedureV2 extends StatelessWidget {
  final String? gateTitle;
  final List<String> steps;
  final String? important;

  /// The procedure is CO TEĎ's one primary action (Reservation board
  /// "POSTUP NA POBOČCE"): looping CTA instead of the text link.
  final bool cta;
  const ResProcedureV2({
    super.key,
    required this.gateTitle,
    required this.steps,
    required this.important,
    this.cta = false,
  });

  void _open(BuildContext context) {
    final tr = t(context);
    showMgSheet<void>(
      context,
      title: tr.tr('pickupProcedure'),
      builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (gateTitle != null) ...[
          Text(gateTitle!, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead)),
          const SizedBox(height: 12),
        ],
        MgStateSteps(steps: steps),
        if (important != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MgColors.warnBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MgColors.warnBorder),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const MgIcon(MgIcons.warn, size: 18, color: MgColors.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(important!,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.warn)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    if (cta) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: MgFabAvoid(
          child: MgCta(label: tr.tr('v2UxRpProcCta'), onTap: () => _open(context), loop: true, arrow: true),
        ),
      );
    }
    // G-458…G-460: a clearly visible white card (not a pale neon link on
    // the light page); at a gate branch the warning shows without opening.
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Semantics(
        button: true,
        label: important != null ? '${tr.tr('pickupProcedure')} · ${tr.tr('gdaProcGateWarn')}' : tr.tr('pickupProcedure'),
        excludeSemantics: true,
        child: MgPress(
          onTap: () => _open(context),
          child: Container(
            key: const ValueKey('res-procedure-v2-entry'),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.tintOkBorder, width: 1.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Row(children: [
                  const MgIcon(MgIcons.compass, size: 20, color: MgColors.link),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr.tr('pickupProcedure'),
                        style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                  ),
                  const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.link),
                ]),
              ),
              if (important != null) ...[
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('res-procedure-v2-warn'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: MgColors.warnBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MgColors.warnBorder),
                  ),
                  child: Row(children: [
                    const MgIcon(MgIcons.warn, size: 16, color: MgColors.warn),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tr.tr('gdaProcGateWarn'),
                          style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.warn)),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
