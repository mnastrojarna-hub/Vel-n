import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../booking/booking_models.dart';
import '../catalog_text.dart';

/// Dark total block of the calculator (V22 §2.4: the one dark block below
/// the steps): "TVOJE CENA · n dny", value 32/900 neon, average per day,
/// rank savings, the ½ offer card (one tap "Nastavit 12:00" = calculator
/// state only) and the rank CTA REZERVOVAT · price. [onBook] null =
/// disabled (availability not loaded / busy day / loyalty retry pending).
class CalcTotalV2 extends StatelessWidget {
  final PriceBreakdown q;

  /// Price at 09:00 and at 12:00 (½ 1st day) for the offer card.
  final PriceBreakdown q9;
  final PriceBreakdown q12;
  final bool late;
  final VoidCallback onSetLate;
  final VoidCallback? onBook;
  final String? rankName;
  final bool loyaltyFailed;
  final VoidCallback onRetryLoyalty;
  final String? blockedReason;

  const CalcTotalV2({
    super.key,
    required this.q,
    required this.q9,
    required this.q12,
    required this.late,
    required this.onSetLate,
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
    final save12 = q9.total - q12.total;
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
          Row(children: [
            Expanded(
              child: Text(tr.tr('v2DetLoyaltyFail'), style: MgType.small.copyWith(color: MgColors.warnDark)),
            ),
            MgBtnText(label: tr.tr('retry'), onTap: onRetryLoyalty, dark: true),
          ]),
        ],
        if (q.days >= 2 && save12 > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: MgColors.neonA(late ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MgColors.neonA(late ? 0.45 : 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
                  child: Center(
                    child: late
                        ? MgIcon(MgIcons.check, size: 18, color: MgColors.onNeon, stroke: 2.6)
                        : Text('½', style: MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      late
                          ? tr.tr('v2CalcLateOn')
                          : '${tr.tr('v2CalcLateTitle')} ${tr.trArgs('v2CalcLateText', {
                              'amount': catMoney(save12),
                              'total': catMoney(q12.total),
                            })}',
                      style: MgType.tab(MgType.small.copyWith(color: MgColors.onDarkLead)),
                    ),
                  ),
                ),
              ]),
              if (!late)
                Align(
                  alignment: Alignment.centerRight,
                  child: MgBtnText(label: tr.tr('v2CalcLateSet'), icon: MgIcons.clock, onTap: onSetLate, dark: true),
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
