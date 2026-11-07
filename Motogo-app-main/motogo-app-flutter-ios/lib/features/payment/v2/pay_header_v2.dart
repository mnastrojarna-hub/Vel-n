import 'package:flutter/material.dart';

import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/v2/booking_header_v2.dart' show BookingStepsV2;

/// Dark rank header of the v2 payment page (Booking board step 3 and the
/// board's "Režim platby"): ‹ = the screen's EXISTING back action, title
/// 17/800 + sub (bike / reservation number), for a new booking the logo
/// ring and the 3-step bar at "Kontrola a platba", then [chip] (the
/// countdown). Bottom padding leaves room for the −24 overlap.
class PayHeaderV2 extends StatelessWidget {
  final String title;
  final String? sub;
  final VoidCallback onBack;
  final bool steps;
  final Widget? chip;

  const PayHeaderV2({
    super.key,
    required this.title,
    this.sub,
    required this.onBack,
    this.steps = false,
    this.chip,
  });

  @override
  Widget build(BuildContext context) {
    final s = sub;
    return MgRankHero(
      ambientKey: 'payment',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MgV2Back(onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(minScale: 0.8, child: Text(title, style: MgType.section.copyWith(color: MgColors.onDark))),
                if (s != null && s.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(s, maxLines: 2, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
                ],
              ]),
            ),
          ),
          if (steps) ...[const SizedBox(width: 8), const MgLogoRing(size: 48)],
        ]),
        if (steps) ...[const SizedBox(height: 12), const BookingStepsV2(current: 2)],
        if (chip != null) ...[const SizedBox(height: 12), chip!],
      ]),
    );
  }
}
