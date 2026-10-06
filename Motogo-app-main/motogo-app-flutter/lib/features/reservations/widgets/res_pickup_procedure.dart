import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/booking_rules.dart';
import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/collapsible_section.dart';
import '../booking_gate_provider.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';

/// „Postup při vyzvednutí“ v detailu rezervace na SAMOOBSLUŽNÉ pobočce
/// (zadání majitele 2026-10-04): rozklikávací (výchozí zabalený) postup bod po
/// bodu — brána (jen pobočka s bránou) → šatna (jen s půjčenou výbavou) →
/// motorka, u brány navíc zvýrazněné „DŮLEŽITÉ“. Jen reserved/active
/// rezervace s převzetím na pobočce (ne přistavení).
class ResPickupProcedure extends ConsumerWidget {
  final Reservation res;
  final List<DoorCode>? codes;
  const ResPickupProcedure({super.key, required this.res, this.codes});

  static bool visibleFor(Reservation r) =>
      (r.status == 'reserved' || r.status == 'active') &&
      (r.displayStatus == ResStatus.nadchazejici || r.displayStatus == ResStatus.aktivni) &&
      r.isSelfService &&
      bookingMethodWithAddress(r.pickupMethod, r.pickupAddress) != 'delivery';

  /// Nárok na šatnu: vydaný/zadržený kód šatny, jinak zrcadlo DB
  /// `_booking_needs_locker` (od 2026-10-05: vybraná velikost základní výbavy
  /// řidiče bez „Mám vlastní výbavu“ — own_gear=false bez jediné velikosti =
  /// nic nepůjčuje, šatna ne; boty a výbava spolujezdce jsou v šatně vždy).
  static bool needsLocker(Reservation r, List<DoorCode>? codes) {
    if (codes != null && codes.isNotEmpty) {
      return codes.any((c) => c.codeType == 'accessories');
    }
    bool has(String? s) => (s ?? '').trim().isNotEmpty;
    return (r.ownGear != true &&
            [r.helmetSize, r.jacketSize, r.pantsSize, r.glovesSize].any(has)) ||
        [
          r.bootsSize,
          r.passengerHelmetSize,
          r.passengerJacketSize,
          r.passengerPantsSize,
          r.passengerBootsSize,
          r.passengerGlovesSize,
        ].any(has);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visibleFor(res)) return const SizedBox.shrink();
    final tr = t(context);
    final gate = ref.watch(bookingGateInfoProvider(res.id)).valueOrNull ?? BookingGateInfo.none;
    final door = gate.lockerDoor;
    final steps = <String>[
      if (gate.hasGate)
        gate.gateCode != null
            ? tr.tr('procStep1Code').replaceAll('{gate}', gate.gateCode!)
            : tr.tr('procStep1NoCode'),
      if (needsLocker(res, codes)) ...[
        door != null
            ? tr.tr('procStep2GearDoor').replaceAll('{n}', '$door')
            : tr.tr('procStep2Gear'),
        tr.tr('procStep3Gear'),
      ] else
        tr.tr('procStep2NoGear'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CollapsibleSection(
        emoji: '🧭',
        title: tr.tr('pickupProcedure'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
        ),
        children: [
          if (gate.hasGate)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(tr.tr('gateProcTitle'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.g500)),
            ),
          for (var i = 0; i < steps.length; i++) _step(i + 1, steps[i]),
          if (gate.hasGate)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MotoGoColors.amberBg,
                border: Border.all(color: MotoGoColors.amberBorder),
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
              ),
              child: Text('⚠️ ${tr.tr('procStepImportant')}',
                  style: const TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
            ),
        ],
      ),
    );
  }

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: MotoGoColors.green, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4, color: MotoGoColors.g600)),
          ),
        ]),
      );
}
