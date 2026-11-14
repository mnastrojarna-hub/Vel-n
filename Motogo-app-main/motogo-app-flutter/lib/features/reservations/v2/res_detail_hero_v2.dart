import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_days.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/v2/chrome/mg_photo_hero.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_hero_photo.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../reservation_models.dart';
import 'res_status_v2.dart';

/// Photo hero of the reservation detail (V22 `.rph`): the bike contained
/// over a dark ground, back disc (photo style → the SAME `backOr` as
/// today), status pill and rating chip (SOS tags stay on the list card and
/// in the history, as in the old app).
class ResDetailHeroV2 extends ConsumerWidget {
  final Reservation res;
  final VoidCallback onBack;
  const ResDetailHeroV2({super.key, required this.res, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final st = res.displayStatus;
    // AFT-02: the same unpaid flag as the list card (pendingBookingFabProvider).
    final unpaid = resPayFlag(res, ref.watch(pendingBookingFabProvider).valueOrNull) == ResPayFlag.unpaid;
    // Krátký telefon (320 × 690): CO TEĎ se vejde do prvního okna.
    final h = (MediaQuery.sizeOf(context).height * 0.34).clamp(220.0, 300.0);
    return MgPhotoHero(
      height: h,
      onBack: onBack,
      image: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        // Sdílená fotka z karty seznamu / lístku Domů (V2 §5.11).
        child: MgHeroPhoto(
          tag: mgHeroTagRes(res.id),
          child: ResBikePhoto(url: res.motoImage, grayscale: st == ResStatus.cancelled, thumbWidth: 1000),
        ),
      ),
      statusPill: ResStatusPill(status: st, live: false, suffix: resStatusSuffix(tr, res)?.toUpperCase(), warn: unpaid),
      // Pilulky nad překryvem listu (−24 px), jako V22 `.pls` (bottom 40).
      bottom: const SizedBox(height: 16),
      tags: [
        if (unpaid) const ResUnpaidChip(),
        if ((res.rating ?? 0) > 0)
          ResPhotoChip(
            label: '${res.rating}/5',
            icon: MgIcons.starFilled,
            iconColor: MgColors.star,
            border: MgColors.star.withValues(alpha: 0.55),
            semanticLabel: '${tr.tr('ratingTitle')} ${tr.trArgs('starsCount', {'n': res.rating})}',
          ),
        // „jen vzhled“: štítky SOS (náhrada / ukončeno SOS) má jako dřív jen
        // karta v seznamu a historie úprav — detail je v původní appce neměl.
      ],
    );
  }
}

/// "za 5 dní" / "zítra" / "dnes" before pickup, "den 2/3" while it runs —
/// from the booking's own dates (Reservation board status pill).
String? resStatusSuffix(AppTranslations tr, Reservation r) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (r.displayStatus) {
    case ResStatus.nadchazejici:
      final start = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
      final n = calendarDaysInclusive(today, start) - 1;
      if (start.isBefore(today)) return null;
      if (n == 0) return tr.tr('v2UxRpToday');
      if (n == 1) return tr.tr('v2UxRpTomorrow');
      return tr.trArgs('v2UxRpInDays', {'n': n, 'days': tr.daysWord(n)});
    case ResStatus.aktivni:
      final total = r.dayCount < 1 ? 1 : r.dayCount;
      final d = calendarDaysInclusive(r.startDate, today).clamp(1, total);
      return tr.trArgs('v2UxRpDayOf', {'d': d, 'n': total});
    case ResStatus.dokoncene:
    case ResStatus.cancelled:
      return null;
  }
}
