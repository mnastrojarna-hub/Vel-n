import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/calendar/trip_day_state.dart';
import '../../../../core/v2/chrome/mg_dock.dart';
import '../../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../catalog_text.dart';

/// Sticky dock of the v2 detail (board `.rk-sticky`): context line (the
/// chosen dates · days, or the hint to pick a date), the docked AI disc
/// (the floating button is hidden on `/moto/:id`) and the rank CTA
/// REZERVOVAT · price. [onReserve] = the page's existing CTA action
/// (PM-3 `startBookingFromSelection`); null while no start date is picked
/// — exactly the old `canProceed` rule (a start alone = single day).
class DetailDockV2 extends StatelessWidget {
  final DateTime? selStart;
  final DateTime? selEnd;
  final int dayCount;

  /// Formatted price for the CTA (null = no complete range yet).
  final String? price;
  final VoidCallback? onReserve;

  const DetailDockV2({
    super.key,
    required this.selStart,
    required this.selEnd,
    required this.dayCount,
    required this.price,
    required this.onReserve,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = selStart;
    final String line;
    if (s == null) {
      line = tr.tr('v2DetDockHint');
    } else if (selEnd == null) {
      line = tripShortDate(tr, s);
    } else {
      line = '${catRange(tr, s, selEnd!)} · ${catDays(tr, dayCount)}';
    }
    return MgDock(
      aiDisc: true,
      contextLine: Text(
        line,
        maxLines: 2,
        style: TextStyle(color: s == null ? MgColors.onDarkMeta : MgColors.onDarkLead),
      ),
      child: MgFabAvoid(
        child: MgCta(
          label: tr.tr('v2CatCtaBook'),
          price: price,
          onTap: onReserve,
          size: MgCtaSize.lg60,
          loop: onReserve != null,
        ),
      ),
    );
  }
}
