import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../booking/booking_ui_helpers.dart' show bookingCard, bookingRadio;
import '../gear_order_state.dart';
import '../v2/gear_branch_v2.dart' show kGearPickupTimes;

/// Krok 1 (starý vzhled): pobočky jako volba, poznámka samoobsluhy nebo
/// orientační čas příchodu (07:00–20:00).
class GearOrderBranch extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  const GearOrderBranch({super.key, required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final br = state.branch;
    return bookingCard(
      1,
      tr.tr('groStepBranch'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final b in state.data!.branches) ...[
          KeyedSubtree(
            key: ValueKey('gear-branch-${b.id}'),
            child: bookingRadio(
              b.name,
              [tr.tr(b.self ? 'groBranchSelf' : 'groBranchStaffed'), if (b.address.isNotEmpty) b.address].join('\n'),
              '',
              b.id == state.branchId,
              () => ctrl.setBranch(b.id),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (br != null && br.self) GearOldNote(tr.tr('groSelfNote')),
        if (br != null && !br.self) ...[
          Text(tr.tr('groPickupTime'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.g600, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: MotoGoColors.g100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MotoGoColors.g200),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('gear-pickup-time'),
                value: kGearPickupTimes.contains(state.pickupTime) ? state.pickupTime : '09:00',
                isExpanded: true,
                items: [
                  for (final h in kGearPickupTimes)
                    DropdownMenuItem(
                        value: h,
                        child: Text(h, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black))),
                ],
                onChanged: (v) => v == null ? null : ctrl.setPickupTime(v),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Drobná poznámka (web `.gr-note`), oranžově jako varování.
class GearOldNote extends StatelessWidget {
  final String text;
  final bool warn;
  const GearOldNote(this.text, {super.key, this.warn = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: warn ? FontWeight.w700 : FontWeight.w600,
            color: warn ? MotoGoColors.amber : MotoGoColors.g600,
          ),
        ),
      );
}
