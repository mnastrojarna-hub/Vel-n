import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';

/// Compact dark rank header of the v2 booking form (board `.rk-hero.bh`):
/// back (dark style, the form's EXISTING back action), title "Rezervace"
/// and the bike — no step bar: the old header had only the title and the
/// bike (owner 2026-11-07 "jen upgrade vzhledu").
/// No countdown chip (the form has none today).
class BookingHeaderV2 extends StatelessWidget {
  final String bikeName;
  final VoidCallback onBack;

  const BookingHeaderV2({
    super.key,
    required this.bikeName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgRankHero(
      ambientKey: 'booking',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MgV2Back(onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('v2BkTitle'), style: MgType.section.copyWith(color: MgColors.onDark)),
                const SizedBox(height: 2),
                Text(bikeName,
                    maxLines: 2,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
              ]),
            ),
          ),
          // CB-29: the board's logo in the tier ring (display only).
          const SizedBox(width: 8),
          const MgLogoRing(size: 48),
        ]),
      ]),
    );
  }
}
