import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/v2/sections/extras_rows_v2.dart' show BookingExtraRowV2;

/// One paid add-on of the edit — the values and the tap closure
/// `EditExtrasSection` builds for its old `_paidCard`.
class EditAddonV2 {
  final String icon;
  final String title;
  final String sub;
  final String price;
  final bool checked;

  /// The tap opens a size sheet (boots) rather than toggling at once.
  final bool opensSheet;
  final VoidCallback onTap;
  const EditAddonV2({
    required this.icon,
    required this.title,
    required this.sub,
    required this.price,
    required this.checked,
    required this.onTap,
    this.opensSheet = false,
  });
}

/// v2 look of the add-on part of `EditExtrasSection` ("Doplňky"): line-icon
/// head, the delivery size note as a T3 banner, the rank benefit line (as
/// in the booking form) and the paid add-ons as the booking's extra rows
/// (✓ box, icon, name, state line, price) — SAME texts, conditions, order
/// and tap closures as the old cards.
class EditAddonsV2 extends StatelessWidget {
  final bool deliveryInfo;
  final bool gearFree;
  final List<EditAddonV2> addons;
  const EditAddonsV2({super.key, required this.deliveryInfo, required this.gearFree, required this.addons});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const MgIcon(MgIcons.bag, size: 18, color: MgColors.link),
        const SizedBox(width: 8),
        Expanded(child: MgWordFit(child: Text(tr.tr('addonsLabel'), style: MgType.eyebrow.copyWith(color: MgColors.ink)))),
      ]),
      const SizedBox(height: 10),
      // Při přistavení potřebujeme velikosti (jako dnes).
      if (deliveryInfo)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MgStateBanner(tone: MgTone.warn, icon: MgIcons.info, title: tr.tr('deliverySizeInfo')),
        ),
      // Od 3. ranku: výbava spolujezdce i veškerá obuv zdarma.
      if (gearFree)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            const MgIcon(MgIcons.crown, size: 18, color: MgColors.link),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr.tr('loyaltyGearBenefit'),
                  style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk)),
            ),
          ]),
        ),
      for (final a in addons)
        BookingExtraRowV2(
          icon: a.icon,
          title: a.title,
          sub: a.sub,
          needSize: false,
          price: a.price,
          selected: a.checked,
          opensSheet: a.opensSheet,
          onTap: a.onTap,
        ),
    ]);
  }
}

/// Caps label over the passenger's inline size pickers (old: green 10/800).
class EditPassengerLabelV2 extends StatelessWidget {
  final String text;
  const EditPassengerLabelV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      MgWordFit(child: Text(text.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta, fontSize: 11)));
}

/// "Vyber aspoň jeden kus" under the rider's sizes (old: amber text).
class EditPickOneV2 extends StatelessWidget {
  final String text;
  const EditPickOneV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: MgIcon(MgIcons.warn, size: 14, color: MgColors.warn)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.warn))),
      ]);
}
