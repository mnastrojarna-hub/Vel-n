import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../reservation_models.dart';
import 'res_fit_v2.dart';
import 'res_status_v2.dart';

/// Compact dark header of the edit (V22 `.ed-h`) with the old header's
/// content: back (to the reservation exactly as today), the title ("Upravit
/// rezervaci"; another [title] gets the caps eyebrow over it), bike · #ID
/// and the "TEĎ" row (photo + today's status, term and length).
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
              if (title != tr.tr('editReservation')) ...[
                Text(tr.tr('editReservation').toUpperCase(),
                    style: MgType.eyebrow.copyWith(color: MgColors.neonText)),
                const SizedBox(height: 4),
              ],
              Semantics(
                header: true,
                child: MgWordFit(minScale: 0.75, child: Text(title, style: MgType.h2.copyWith(color: MgColors.onDark))),
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
          // Termín a stav vedle štítku TEĎ a ceny, jen když se vejdou celými
          // slovy (fr / nl / en na 320 dp s velkým písmem) — jinak štítek a
          // cena nahoře a termín se stavem pod nimi přes celou šířku.
          child: LayoutBuilder(builder: (context, c) {
            final photo = ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 44, height: 32, child: ResBikePhoto(url: booking.motoImage, thumbWidth: 160)),
            );
            final nowStyle = MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText);
            final now = Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: MgColors.neonA(0.16), borderRadius: BorderRadius.circular(999)),
              child: Text(tr.tr('v2ResEditNow'), style: nowStyle),
            );
            final rangeStyle = MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkBody));
            // The old header: term + "Aktivní / Nadcházející · n dní".
            final range = '${isActive ? tr.active : tr.upcoming} · ${resRangeDays(tr, booking)}';
            final lines = Semantics(
              label: '${isActive ? tr.active : tr.upcoming}, ${resRangeDays(tr, booking)}, $days',
              excludeSemantics: true,
              child: Text(range, style: rangeStyle),
            );
            final textW = c.maxWidth - 44 - 8 - (resLineWidth(context, tr.tr('v2ResEditNow'), nowStyle) + 16) - 8;
            final inline = resLineFits(context, range, rangeStyle, textW, minScale: 0.85);
            if (inline) {
              return Row(children: [
                photo,
                const SizedBox(width: 8),
                now,
                const SizedBox(width: 8),
                Expanded(child: MgWordFit(minScale: 0.85, child: lines)),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              photo,
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  now,
                  const SizedBox(height: 4),
                  lines,
                ]),
              ),
            ]);
          }),
        ),
      ]),
    );
  }
}
