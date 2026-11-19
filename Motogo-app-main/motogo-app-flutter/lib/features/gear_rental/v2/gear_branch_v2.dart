import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../booking/v2/booking_v2_parts.dart' show BkCard, BkLabel, BkSizeChip;
import '../gear_offer_provider.dart';
import '../gear_order_state.dart';

/// Hodiny „Kdy přijdeš (orientačně)“ — 07:00 až 20:00 po hodině (web).
const List<String> kGearPickupTimes = [
  '07:00', '08:00', '09:00', '10:00', '11:00', '12:00', '13:00',
  '14:00', '15:00', '16:00', '17:00', '18:00', '19:00', '20:00',
];

/// Krok 1 „Kde si výbavu vyzvedneš“: pobočky jako volba (název, typ,
/// adresa); samoobsluha = poznámka o kódech, obsluha = orientační čas.
class GearBranchV2 extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  const GearBranchV2({super.key, required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final br = state.branch;
    return BkCard(
      key: const ValueKey('gear-step-branch'),
      icon: MgIcons.pin,
      title: tr.tr('groStepBranch'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final b in state.data!.branches) ...[
          GearBranchRowV2(branch: b, selected: b.id == state.branchId, onTap: () => ctrl.setBranch(b.id)),
          const SizedBox(height: 8),
        ],
        if (br != null && br.self) GearNoteV2(tr.tr('groSelfNote')),
        if (br != null && !br.self) ...[
          const SizedBox(height: 4),
          BkLabel(tr.tr('groPickupTime')),
          const SizedBox(height: 8),
          SingleChildScrollView(
            key: const ValueKey('gear-pickup-times'),
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final h in kGearPickupTimes) ...[
                BkSizeChip(label: h, selected: state.pickupTime == h, onTap: () => ctrl.setPickupTime(h)),
                const SizedBox(width: 6),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Volba pobočky (vzhled `BkOptionRow`, bez ceny).
class GearBranchRowV2 extends StatelessWidget {
  final GearBranch branch;
  final bool selected;
  final VoidCallback onTap;
  const GearBranchRowV2({super.key, required this.branch, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dur = MgMotion.of(context, MgMotion.color);
    final kind = tr.tr(branch.self ? 'groBranchSelf' : 'groBranchStaffed');
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${branch.name}, $kind, ${branch.address}',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey('gear-branch-${branch.id}'),
          duration: dur,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MgColors.surface : MgColors.well,
            borderRadius: BorderRadius.circular(MgRadius.button),
            border: Border.all(color: selected ? MgColors.ink : MgColors.line, width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: dur,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? MgColors.ink : MgColors.surface,
                border: Border.all(color: selected ? MgColors.ink : MgColors.lineInput, width: 1.5),
              ),
              child: selected
                  ? MgPop(trigger: selected, child: Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.neon, stroke: 2.6)))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(branch.name, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink, height: 1.3)),
                const SizedBox(height: 2),
                Text(kind, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.link)),
                if (branch.address.isNotEmpty) Text(branch.address, style: MgType.small.copyWith(color: MgColors.lead)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Drobná poznámka pod volbou (web `.gr-note`).
class GearNoteV2 extends StatelessWidget {
  final String text;
  final Color? color;
  final String icon;
  const GearNoteV2(this.text, {super.key, this.color, this.icon = MgIcons.info});

  @override
  Widget build(BuildContext context) {
    final c = color ?? MgColors.lead;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MgIcon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: MgType.small.copyWith(color: c, fontWeight: color == null ? null : FontWeight.w700))),
      ]),
    );
  }
}
