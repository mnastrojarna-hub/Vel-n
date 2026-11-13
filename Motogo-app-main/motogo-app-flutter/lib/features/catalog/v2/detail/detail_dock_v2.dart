import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/calendar/trip_day_state.dart';
import '../../../../core/v2/chrome/mg_dock.dart';
import '../../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../catalog_text.dart';

/// Sticky dock of the v2 detail (board `.rk-sticky`): context line (the
/// chosen dates · days, or the hint to pick a date), the docked AI disc
/// (the floating button is hidden on `/moto/:id`) and the rank CTA.
/// No date yet (DESIGN_V2 MotoDetail sticky bar, Stavy 9.1): "VYBRAT
/// TERMÍN · od 2 727 Kč/den" → [onPickDates] opens the date step — never a
/// dead button. Otherwise REZERVOVAT · price → [onReserve] = the page's
/// existing CTA action (PM-3 `startBookingFromSelection`; a start alone =
/// single day, exactly the old `canProceed` rule). [busy] (a carried range
/// with a booked day, DESIGN_V2 sticky bar "busy"): the dates in amber and
/// "ZMĚNIT TERMÍN" → [onPickDates] instead of REZERVOVAT.
class DetailDockV2 extends StatelessWidget {
  final DateTime? selStart;
  final DateTime? selEnd;
  final int dayCount;

  /// Formatted price for the CTA (null = no complete range yet).
  final String? price;

  /// "od 2 727 Kč/den" for the no-date CTA (null = no price list).
  final String? fromPrice;
  final VoidCallback? onPickDates;
  final VoidCallback? onReserve;
  final bool busy;

  /// CB-17: "Rozpis" next to the trip line (null = hidden).
  final VoidCallback? onBreakdown;

  /// First problem of the chosen range (licence, own overlapping booking,
  /// min / max days — `bookingRangeErrors`), shown in red in the dock so it
  /// is seen without scrolling (G-152/G-153/G-154). The CTA stays enabled
  /// as in the old look (the booking form blocks), only its loop stops.
  final String? warning;

  const DetailDockV2({
    super.key,
    required this.selStart,
    required this.selEnd,
    required this.dayCount,
    required this.price,
    required this.onReserve,
    this.fromPrice,
    this.onPickDates,
    this.busy = false,
    this.onBreakdown,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = selStart;
    final String line;
    if (s == null) {
      line = tr.tr('v2DetDockHint');
    } else if (selEnd == null) {
      // P2-02: a start alone books ONE day (old `canProceed` rule, kept) —
      // say so, so nobody pays for 1 day thinking of a longer trip.
      line = '${tripShortDate(tr, s)} · ${catDays(tr, 1).replaceAll(' ', '\u00A0')}';
    } else {
      line = '${catRange(tr, s, selEnd!)} · ${catDays(tr, dayCount).replaceAll(' ', '\u00A0')}';
    }
    final change = busy && s != null && onPickDates != null;
    final pick = (s == null || change) && onPickDates != null;
    final warn = pick ? null : warning;
    final Widget text = warn != null
        ? Row(key: const ValueKey('detail-dock-warning'), crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1, right: 6),
              child: MgIcon(MgIcons.alert, size: 18, color: MgColors.errDark),
            ),
            Expanded(
              child: Text(warn,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MgColors.errDark, fontWeight: FontWeight.w700)),
            ),
          ])
        : s != null && selEnd == null && !change
            ? Column(key: const ValueKey('detail-dock-one-day'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line, maxLines: 1, style: const TextStyle(color: MgColors.onDarkLead)),
                Text(tr.tr('v2DetDockOneDay'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MgColors.warnDark, fontWeight: FontWeight.w700)),
              ])
            : Text(
                line,
                maxLines: 2,
                style: TextStyle(color: change ? MgColors.warnDark : (s == null ? MgColors.onDarkMeta : MgColors.onDarkLead)),
              );
    // No AI disc: the old detail had no AI entry (only Domů / SOS).
    return MgDock(
      contextLine: onBreakdown == null || pick || warn != null
          ? text
          : Row(children: [
              Expanded(child: text),
              MgBtnText(label: tr.tr('v2Breakdown'), icon: MgIcons.chevronUp, dark: true, onTap: onBreakdown),
            ]),
      child: MgFabAvoid(
        child: pick
            ? MgCta(
                label: tr.tr(change ? 'psChangeDates' : 'v2CalcPickDatesCta'),
                price: change ? null : fromPrice,
                onTap: onPickDates,
                size: MgCtaSize.lg60,
                loop: true,
              )
            : warn != null
                // J4: with a warning the reserve stays enabled (as in the
                // old look — the form blocks) but no longer reads as "go".
                ? MgBtnGhostDark(
                    key: const ValueKey('detail-dock-reserve-ghost'),
                    label: [tr.tr('v2CatCtaBook').toUpperCase(), if (price != null) price!].join(' · '),
                    height: 60,
                    onTap: onReserve,
                  )
                : MgCta(
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
