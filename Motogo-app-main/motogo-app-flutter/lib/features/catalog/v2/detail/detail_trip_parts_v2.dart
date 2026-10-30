import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../booking/booking_models.dart';
import '../calc/calc_parts_v2.dart';

/// ② "Předání a výbava" of the detail's "Tvoje jízda": nothing to choose
/// here (place, time, gear and sizes are chosen in the booking form), so an
/// "i" tile instead of a step number that would never be done. With a range
/// of 2+ days it also tells the concrete 12:00 saving (owner 2026-10-22:
/// „jako informace ano“) — computed exactly as the calculator's total
/// ([quote] standard pickup − [quote12] pickup from 12:00).
class DetailHandoverInfoV2 extends StatelessWidget {
  final PriceBreakdown? quote;
  final PriceBreakdown? quote12;
  const DetailHandoverInfoV2({super.key, required this.quote, required this.quote12});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final q = quote, q12 = quote12;
    final save = q != null && q12 != null && q.days >= 2 ? q.total - q12.total : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CalcInfoBadge(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              header: true,
              child: Text(tr.tr('v2DetStepHandover'), style: MgType.section.copyWith(color: MgColors.ink)),
            ),
            const SizedBox(height: 4),
            Text(tr.tr('v2DetHandoverLater'), style: MgType.small.copyWith(color: MgColors.lead)),
          ]),
        ),
      ]),
      if (save > 0) ...[
        const SizedBox(height: 12),
        CalcHalfInfo(save: save, total: q12!.total, dark: false),
      ],
    ]);
  }
}
