import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_space.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../booking_v2_parts.dart';
import 'extras_rows_v2.dart';

/// v2 look of `BookingFormExtrasSection` (V branch): basic free gear box,
/// "Mám vlastní výbavu" (the SAME check closure), the size rows (hidden
/// with own gear, as today), the rank benefit line ("zdarma s rankem" is a
/// meaning chip, never rank colour), the extras rows and the trailer row —
/// all built by the section with its EXISTING closures.
class BookingExtrasV2 extends StatelessWidget {
  final bool ownGear;
  final ValueChanged<bool> onOwnGear;
  final List<BookingGearRowV2> gearRows;
  final bool gearFree;
  final List<Widget> items;
  final Widget? trailer;

  const BookingExtrasV2({
    super.key,
    required this.ownGear,
    required this.onOwnGear,
    required this.gearRows,
    required this.gearFree,
    required this.items,
    this.trailer,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return BkCard(
      icon: MgIcons.helmet,
      title: tr.tr('v2BkGearTitle'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Základní výbava zdarma.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MgColors.tintOk,
            borderRadius: BorderRadius.circular(MgRadius.action),
            border: Border.all(color: MgColors.tintOkBorder),
          ),
          child: Row(children: [
            MgIcon(MgIcons.shield, size: 22, color: MgColors.link),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(
                  child: Text(tr.tr('basicGearFree'),
                      style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk, height: 1.3)),
                ),
                MgWordFit(child: Text(tr.tr('basicGearList'), style: MgType.small.copyWith(color: MgColors.onTintOk))),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
              child: Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.onNeon, stroke: 2.6)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        MgCheckRow(value: ownGear, onChanged: onOwnGear, label: tr.tr('ownGear')),
        bkAnimatedSize(
          context,
          ownGear || gearRows.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    BkLabel(tr.tr('v2BkSizesLabel')),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(tr.tr('v2BkSizesHint'), style: MgType.small.copyWith(color: MgColors.lead)),
                    ),
                    ...gearRows,
                  ]),
                ),
        ),
        const SizedBox(height: 8),
        BkLabel(tr.tr('v2BkExtrasLabel')),
        if (gearFree)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MgEnter(
              child: Row(children: [
                MgIcon(MgIcons.crown, size: 18, color: MgColors.link),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr.tr('loyaltyGearBenefit'),
                      style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk)),
                ),
              ]),
            ),
          ),
        ...items,
        if (trailer != null) trailer!,
      ]),
    );
  }
}
