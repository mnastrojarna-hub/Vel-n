import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_photo_hero.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../reservation_models.dart';
import 'res_status_v2.dart';

/// Photo hero of the reservation detail (V22 `.rph`): the bike contained
/// over a dark ground, back disc (photo style → the SAME `backOr` as
/// today), status pill, rating chip and the SOS tags of the old card.
class ResDetailHeroV2 extends StatelessWidget {
  final Reservation res;
  final VoidCallback onBack;
  const ResDetailHeroV2({super.key, required this.res, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final st = res.displayStatus;
    return MgPhotoHero(
      height: 300,
      onBack: onBack,
      image: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: ResBikePhoto(url: res.motoImage, grayscale: st == ResStatus.cancelled, thumbWidth: 1000),
      ),
      statusPill: ResStatusPill(status: st, live: false),
      // Pilulky nad překryvem listu (−24 px), jako V22 `.pls` (bottom 40).
      bottom: const SizedBox(height: 16),
      tags: [
        if ((res.rating ?? 0) > 0)
          ResPhotoChip(
            label: '${res.rating}/5',
            icon: MgIcons.starFilled,
            iconColor: MgColors.star,
            border: MgColors.star.withValues(alpha: 0.55),
            semanticLabel: '${tr.tr('ratingTitle')} ${tr.trArgs('starsCount', {'n': res.rating})}',
          ),
        if (res.sosReplacement)
          ResPhotoChip(
            label: tr.tr('replacementForSos'),
            icon: MgIcons.swap,
            iconColor: MgColors.neon,
            border: MgColors.neonA(0.5),
          ),
        if (res.endedBySos)
          ResPhotoChip(
            label: tr.tr('endedBySos'),
            icon: MgIcons.sos,
            iconColor: MgColors.sosDot,
            border: MgColors.sosDot.withValues(alpha: 0.7),
          ),
      ],
    );
  }
}

/// Title block on the canvas sheet: "REZERVACE #ID", bike, category ·
/// branch, the date range and length (today's Kategorie / Datum / Délka).
class ResTitleBlockV2 extends StatelessWidget {
  final Reservation res;
  const ResTitleBlockV2({super.key, required this.res});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final meta = [
      if ((res.category ?? '').isNotEmpty) res.category!,
      if ((res.branchName ?? '').isNotEmpty) res.branchName!,
    ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MgEyebrow(tr.trArgs('v2ResEyebrowId', {'id': res.shortId}), dark: false),
      const SizedBox(height: 8),
      Semantics(
        header: true,
        child: Text(res.motoName, style: MgType.h1.copyWith(color: MgColors.ink)),
      ),
      if (meta.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(meta, style: MgType.small.copyWith(color: MgColors.lead)),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(res.dateRange, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
          child: Text(resDays(tr, res.dayCount),
              style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark))),
        ),
      ]),
    ]);
  }
}
