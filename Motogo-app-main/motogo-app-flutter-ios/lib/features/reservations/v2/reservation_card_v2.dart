import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../reservation_models.dart';
import 'res_card_actions_v2.dart';
import 'res_fit_v2.dart';
import 'res_status_v2.dart';

/// v2 reservation card (V22 `.ls-c`): photo with status pill / needs-action
/// badge / rating, then Termín · Délka · Celkem, then the ticket strip
/// ([ResCardActionsV2]: dark on the list's one card that needs
/// action, white on the others) with the SAME actions per status as
/// today's `ReservationCard` (Detail · Upravit · SOS / Detail jízdy ·
/// Hodnotit / Detail · Obnovit).
/// No storno on the card (today's card does not offer it either).
class ReservationCardV2 extends ConsumerWidget {
  final Reservation reservation;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  /// Zrušená rezervace → „Obnovit" = obnovit a zaplatit (D3, jako
  /// `ReservationCard.onRestore`); bez něj otevře detail.
  final VoidCallback? onRestore;
  final ResPayFlag payFlag;

  /// The list's one card that needs action ([resPrimaryCardId]): dark rank
  /// stub with the glowing CTA; false = white stub (V22 R5.2).
  final bool primary;

  const ReservationCardV2({
    super.key,
    required this.reservation,
    required this.onTap,
    this.onEdit,
    this.onRestore,
    this.payFlag = ResPayFlag.none,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final r = reservation;
    final st = r.displayStatus;
    final grayscale = st == ResStatus.dokoncene || st == ResStatus.cancelled;
    final needsAction = payFlag != ResPayFlag.none;
    return Container(
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: needsAction ? MgColors.warnBorder : MgColors.line, width: needsAction ? 2 : 1),
        boxShadow: MgShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(needsAction ? 14 : 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            label: '${r.motoName}, ${resStatusLabel(tr, st)}, ${r.dateRange}',
            excludeSemantics: true,
            child: MgPress(
              scale: 0.99,
              onTap: onTap,
              child: SizedBox(height: 156, child: _photo(tr, st, grayscale)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            // Termín · Délka · Celkem v jednom řádku, jen když se popisky
            // vejdou celé (es „DURACIÓN", uk „ТРИВАЛІСТЬ" na 320 / 360 dp
            // s velkým písmem) — jinak termín nahoře přes celou šířku.
            child: LayoutBuilder(builder: (context, c) {
              final date = _info(tr.date, r.dateRange);
              final days = _info(tr.tr('resDuration'), resDays(tr, r.dayCount));
              final total = _info(tr.tr('total'), Money.czk(r.totalPrice), price: true);
              final unit = (c.maxWidth - 16) / 33;
              bool fits(String label, int flex) =>
                  resLineFits(context, label.toUpperCase(), _infoLabel, unit * flex, minScale: _infoMinScale);
              if (fits(tr.date, 15) && fits(tr.tr('resDuration'), 8) && fits(tr.tr('total'), 10)) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 15, child: date),
                  const SizedBox(width: 8),
                  Expanded(flex: 8, child: days),
                  const SizedBox(width: 8),
                  Expanded(flex: 10, child: total),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                date,
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: days),
                  const SizedBox(width: 8),
                  Expanded(child: total),
                ]),
              ]);
            }),
          ),
          ResCardActionsV2(
            reservation: r,
            onTap: onTap,
            onEdit: onEdit,
            onRestore: onRestore,
            primary: primary,
          ),
        ]),
      ),
    );
  }

  Widget _photo(AppTranslations tr, ResStatus st, bool grayscale) {
    final r = reservation;
    return Stack(fit: StackFit.expand, children: [
      ResBikePhoto(url: r.motoImage, grayscale: grayscale),
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [MgColors.nightA(0.5), MgColors.nightA(0), MgColors.nightA(0), MgColors.nightA(0.9)],
              stops: const [0, 0.34, 0.45, 1],
            ),
          ),
        ),
      ),
      // Stav vlevo, „Nezaplaceno" / ověřování vpravo; když se oba nevejdou
      // celé do řádku (de „BEVORSTEHEND" na 320 dp), štítek platby pod stav.
      Positioned(
        top: 10,
        left: 10,
        right: 10,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            ResStatusPill(status: st, live: false),
            if (payFlag != ResPayFlag.none)
              ResPhotoChip(
                label: tr.tr(payFlag == ResPayFlag.verifying ? 'psPendingTitle' : 'payStatusUnpaid'),
                icon: payFlag == ResPayFlag.verifying ? MgIcons.clock : MgIcons.card,
                iconColor: MgColors.warnDark,
                border: MgColors.warnDark.withValues(alpha: 0.6),
                textColor: MgColors.warnDark,
              ),
          ],
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 10,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.motoName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.title.copyWith(fontSize: 17, color: MgColors.onDark)),
              Text(r.shortId, style: MgType.meta.copyWith(color: MgColors.onDarkSecondary)),
            ]),
          ),
          if (r.sosReplacement || r.endedBySos) ...[
            const SizedBox(width: 6),
            ResPhotoChip(
              label: 'SOS',
              icon: MgIcons.sos,
              iconColor: r.sosReplacement ? MgColors.neon : MgColors.sosDot,
              border: r.sosReplacement ? MgColors.neonA(0.5) : MgColors.sosDot.withValues(alpha: 0.7),
              semanticLabel: tr.tr(r.sosReplacement ? 'replacementForSos' : 'endedBySos'),
            ),
          ],
          if ((r.rating ?? 0) > 0) ...[
            const SizedBox(width: 6),
            ResPhotoChip(
              label: '${r.rating}/5',
              icon: MgIcons.starFilled,
              iconColor: MgColors.star,
              border: MgColors.star.withValues(alpha: 0.55),
              semanticLabel: '${tr.tr('ratingTitle')} ${tr.trArgs('starsCount', {'n': r.rating})}',
            ),
          ],
        ]),
      ),
    ]);
  }

  static final _infoLabel = MgType.micro.copyWith(letterSpacing: 0.4, color: MgColors.meta);
  static const _infoMinScale = 0.7;

  Widget _info(String label, String value, {bool price = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MgWordFit(
            minScale: _infoMinScale,
            child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _infoLabel),
          ),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 2,
              style: MgType.tab(MgType.small.copyWith(
                  fontWeight: FontWeight.w800, color: price ? MgColors.link : MgColors.ink))),
        ],
      );
}
