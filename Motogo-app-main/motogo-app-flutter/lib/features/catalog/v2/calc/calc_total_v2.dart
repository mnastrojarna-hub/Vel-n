import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../booking/booking_models.dart';
import '../catalog_text.dart';

/// Dark total block of the calculator (V22 §2.4: the one dark block below
/// the steps): "TVOJE CENA · n dny" = the standard-pickup price, value
/// 32/900 neon, average per day, rank savings, the ½ INFO card (owner
/// 2026-10-22: no toggle — the concrete 12:00 saving, the time is chosen in
/// the booking form) and the rank CTA REZERVOVAT · price. [onBook] null =
/// disabled (availability not loaded / busy day / loyalty retry pending).
class CalcTotalV2 extends StatelessWidget {
  /// Standard pickup (the booking form's 09:00 default).
  final PriceBreakdown q;

  /// The same trip with pickup from 12:00 (½ 1st day) — info only.
  final PriceBreakdown q12;
  final VoidCallback? onBook;
  final String? rankName;
  final bool loyaltyFailed;
  final VoidCallback onRetryLoyalty;
  final String? blockedReason;

  const CalcTotalV2({
    super.key,
    required this.q,
    required this.q12,
    required this.onBook,
    required this.onRetryLoyalty,
    this.rankName,
    this.loyaltyFailed = false,
    this.blockedReason,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final days = q.days < 1 ? 1 : q.days;
    final save12 = q.total - q12.total;
    final saved = q.loyaltyDiscount > 0 && rankName != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: MgGradients.darkCta,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MgColors.neonA(0.25)),
        boxShadow: MgShadows.dark,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${tr.tr('v2YourPrice')} · ${catDays(tr, days)}'.toUpperCase(),
            style: MgType.eyebrow.copyWith(color: MgColors.neonText)),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          child: MgBump(
            trigger: q.total,
            child: Text(catMoney(q.total),
                style: MgType.tab(MgType.display.copyWith(
                  color: MgColors.neon,
                  shadows: [Shadow(color: MgColors.neonA(0.35), blurRadius: 18)],
                ))),
          ),
        ),
        const SizedBox(height: 4),
        Text(tr.trArgs('v2AvgPerDay', {'amount': catMoney((q.total / days).roundToDouble())}),
            style: MgType.tab(MgType.small.copyWith(color: MgColors.onDarkLead))),
        if (saved) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: MgPop(
              trigger: q.loyaltyDiscount,
              playOnMount: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MgColors.white(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.white(0.14)),
                ),
                child: Text(
                  tr.trArgs('v2CalcRankSaved', {'rank': rankName, 'amount': catMoney(q.loyaltyDiscount)}),
                  style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark)),
                ),
              ),
            ),
          ),
        ],
        if (loyaltyFailed) ...[
          const SizedBox(height: 10),
          // Full-width note, retry under it (never "loy|aliteitskorting").
          MgWordFit(child: Text(tr.tr('v2DetLoyaltyFail'), style: MgType.small.copyWith(color: MgColors.warnDark))),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MgBtnText(label: tr.tr('retry'), onTap: onRetryLoyalty, dark: true),
          ),
        ],
        if (q.days >= 2 && save12 > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: MgColors.neonA(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MgColors.neonA(0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                label: tr.tr('v2BkHalfA11y'),
                child: ExcludeSemantics(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
                    child: Center(
                      child: Text('½', style: MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 2),
                  Text(tr.tr('v2LpCalcTitle'),
                      style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
                  const SizedBox(height: 2),
                  Text(
                    tr.trArgs('v2LpCalcSave', {'amount': catMoney(save12), 'total': catMoney(q12.total)}),
                    style: MgType.tab(MgType.small.copyWith(color: MgColors.onDarkLead)),
                  ),
                ]),
              ),
            ]),
          ),
        ] else if (q.days < 2) ...[
          const SizedBox(height: 10),
          Text(tr.tr('v2CalcLateOne'), style: MgType.small.copyWith(color: MgColors.onDarkMeta)),
        ],
        const SizedBox(height: 14),
        if (blockedReason != null) ...[
          Text(blockedReason!, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.warnDark)),
          const SizedBox(height: 8),
        ],
        MgFabAvoid(
          child: MgCta(
            label: tr.tr('v2CatCtaBook'),
            price: onBook == null ? null : catMoney(q.total),
            onTap: onBook,
            size: MgCtaSize.lg60,
            loop: onBook != null,
          ),
        ),
      ]),
    );
  }
}
