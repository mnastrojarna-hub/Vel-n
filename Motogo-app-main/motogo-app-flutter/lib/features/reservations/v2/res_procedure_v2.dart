import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_parts.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 look of `ResPickupProcedure` (self-service pickup steps). Today the
/// steps sit in a collapsed section; here the same steps open from a link
/// in CO TEĎ into a light sheet (V22 "Postup na pobočce"). The widget keeps
/// computing the steps (gate / locker / no gear) — this only draws them.
class ResProcedureV2 extends StatelessWidget {
  final String? gateTitle;
  final List<String> steps;
  final String? important;
  const ResProcedureV2({super.key, required this.gateTitle, required this.steps, required this.important});

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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: true,
        label: tr.tr('pickupProcedure'),
        excludeSemantics: true,
        child: MgPress(
          onTap: () => _open(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(children: [
              const MgIcon(MgIcons.compass, size: 18, color: MgColors.neonText),
              const SizedBox(width: 8),
              Flexible(
                child: Text(tr.tr('pickupProcedure'),
                    style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
              ),
              const SizedBox(width: 4),
              const MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.neonText),
            ]),
          ),
        ),
      ),
    );
  }
}
