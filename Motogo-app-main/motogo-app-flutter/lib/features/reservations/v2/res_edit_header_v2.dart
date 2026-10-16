import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../reservation_models.dart';
import 'res_status_v2.dart';

/// Compact dark header of the edit (V22 `.ed-h`): back (chooser → back to
/// the reservation exactly as today; focused intent → back to the chooser),
/// "UPRAVIT REZERVACI", the title, bike · #ID and the "TEĎ" row (today's
/// term, status, length, price).
class ResEditHeaderV2 extends StatelessWidget {
  final Reservation booking;
  final bool isActive;
  final String title;
  final VoidCallback onBack;
  const ResEditHeaderV2({
    super.key,
    required this.booking,
    required this.isActive,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final days = '${booking.dayCount} ${tr.daysWord(booking.dayCount)}';
    return MgRankHero(
      ambientKey: 'reservation-edit',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          MgV2Back(onTap: onBack, style: MgBackStyle.dark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.tr('editReservation').toUpperCase(),
                  style: MgType.eyebrow.copyWith(color: MgColors.neonText)),
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(title, style: MgType.h2.copyWith(color: MgColors.onDark)),
              ),
              Text('${booking.motoName} · ${booking.shortId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.small.copyWith(color: MgColors.onDarkSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            color: MgColors.white(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MgColors.white(0.12)),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 44, height: 32, child: ResBikePhoto(url: booking.motoImage, thumbWidth: 160)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: MgColors.neonA(0.16), borderRadius: BorderRadius.circular(999)),
              child: Text(tr.tr('v2ResEditNow'), style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(resRangeShort(tr, booking),
                    style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkBody))),
                Text('${isActive ? tr.active : tr.upcoming} · $days',
                    style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(Money.czk(booking.totalPrice),
                style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark))),
          ]),
        ),
      ]),
    );
  }
}
