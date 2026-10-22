import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../reservation_models.dart';
import 'res_fit_v2.dart';
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
            final priceStyle = MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark));
            final price = Text(Money.czk(booking.totalPrice), style: priceStyle);
            final rangeStyle = MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkBody));
            final stateStyle = MgType.meta.copyWith(color: MgColors.onDarkMeta);
            final state = '${isActive ? tr.active : tr.upcoming} · $days';
            final lines = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgWordFit(minScale: 0.8, child: Text(resRangeShort(tr, booking), style: rangeStyle)),
              MgWordFit(minScale: 0.75, child: Text(state, style: stateStyle)),
            ]);
            final textW = c.maxWidth - 44 - 8 - (resLineWidth(context, tr.tr('v2ResEditNow'), nowStyle) + 16) - 8 - 8 -
                resLineWidth(context, Money.czk(booking.totalPrice), priceStyle);
            final inline = resWordsFit(context, state, stateStyle, textW, minScale: 0.85) &&
                resWordsFit(context, resRangeShort(tr, booking), rangeStyle, textW, minScale: 0.85);
            if (inline) {
              return Row(children: [
                photo,
                const SizedBox(width: 8),
                now,
                const SizedBox(width: 8),
                Expanded(child: lines),
                const SizedBox(width: 8),
                price,
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              photo,
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [now, const SizedBox(width: 8), const Spacer(), price]),
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
