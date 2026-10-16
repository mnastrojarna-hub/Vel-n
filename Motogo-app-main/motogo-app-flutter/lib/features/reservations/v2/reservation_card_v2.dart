import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../reservation_models.dart';
import 'res_status_v2.dart';

/// v2 reservation card (V22 `.ls-c`): photo with status pill / needs-action
/// badge / rating, then Termín · Délka · Celkem, then a dark ticket strip
/// with the SAME actions per status as today's `ReservationCard`
/// (Detail · Upravit · SOS / Detail jízdy · Hodnotit / Detail · Obnovit).
/// No storno on the card (today's card does not offer it either).
class ReservationCardV2 extends ConsumerWidget {
  final Reservation reservation;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  /// Zrušená rezervace → „Obnovit" = obnovit a zaplatit (D3, jako
  /// `ReservationCard.onRestore`); bez něj otevře detail.
  final VoidCallback? onRestore;
  final ResPayFlag payFlag;

  const ReservationCardV2({
    super.key,
    required this.reservation,
    required this.onTap,
    this.onEdit,
    this.onRestore,
    this.payFlag = ResPayFlag.none,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final r = reservation;
    final st = r.displayStatus;
    final rank = ref.watch(rankTokensProvider);
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
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 15, child: _info(tr.date, r.dateRange)),
              const SizedBox(width: 8),
              Expanded(flex: 8, child: _info(tr.tr('resDuration'), resDays(tr, r.dayCount))),
              const SizedBox(width: 8),
              Expanded(flex: 10, child: _info(tr.tr('total'), Money.czk(r.totalPrice), price: true)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(gradient: MgGradients.hero(rank.aura)),
            // Úzký telefon (320 dp): tlačítka pod sebou na celou šířku, ať se
            // „Wiederherstellen" / „Редагувати" nikdy nedělí uprostřed slova.
            child: LayoutBuilder(builder: (context, c) {
              if (c.maxWidth >= 300) return Row(children: _actions(context, tr, st));
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _stacked(context, tr, st));
            }),
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
      Positioned(
        top: 10,
        left: 10,
        right: needsBadgeWidth,
        child: Align(alignment: Alignment.centerLeft, child: ResStatusPill(status: st, live: false)),
      ),
      if (payFlag != ResPayFlag.none)
        Positioned(
          top: 10,
          right: 10,
          child: ResPhotoChip(
            label: tr.tr(payFlag == ResPayFlag.verifying ? 'psPendingTitle' : 'payStatusUnpaid'),
            icon: payFlag == ResPayFlag.verifying ? MgIcons.clock : MgIcons.card,
            iconColor: MgColors.warnDark,
            border: MgColors.warnDark.withValues(alpha: 0.6),
            textColor: MgColors.warnDark,
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

  double get needsBadgeWidth => payFlag == ResPayFlag.none ? 10 : 150;

  Widget _info(String label, String value, {bool price = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MgWordFit(
            minScale: 0.7,
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MgType.micro.copyWith(letterSpacing: 0.4, color: MgColors.meta)),
          ),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 2,
              style: MgType.tab(MgType.small.copyWith(
                  fontWeight: FontWeight.w800, color: price ? MgColors.link : MgColors.ink))),
        ],
      );

  List<Widget> _actions(BuildContext context, AppTranslations tr, ResStatus st) {
    final r = reservation;
    Widget cta(String label) => Expanded(
          child: MgCta(label: label, onTap: onTap, size: MgCtaSize.sm48, showMarks: false),
        );
    Widget ghost(String label, VoidCallback onPressed) => Expanded(
          child: MgBtnGhostDark(label: label, onTap: onPressed, height: 48),
        );
    const gap = SizedBox(width: 8);
    switch (st) {
      case ResStatus.aktivni:
        // Se SOS: Detail jen na šířku popisku, SOS jako ikona (48 px) — ať se
        // „Upravit" vejde celé i v delších jazycích (de „Bearbeiten").
        if (r.sosAllowed) {
          return [
            MgCta(label: tr.detail, onTap: onTap, size: MgCtaSize.sm48, showMarks: false, expand: false),
            if (onEdit != null) ...[gap, ghost(tr.edit, onEdit!)] else const Spacer(),
            gap,
            _SosButton(label: tr.tr('breakdownBtn')),
          ];
        }
        return [
          cta(tr.detail),
          if (onEdit != null) ...[gap, ghost(tr.edit, onEdit!)],
        ];
      case ResStatus.nadchazejici:
        return [
          cta(tr.detail),
          if (onEdit != null) ...[gap, ghost(tr.edit, onEdit!)],
        ];
      case ResStatus.dokoncene:
        return [cta(tr.tr('rideDetail')), gap, ghost(tr.tr('rateBtn'), onTap)];
      case ResStatus.cancelled:
        return [cta(tr.detail), gap, ghost(tr.tr('restoreBtn'), onRestore ?? onTap)];
    }
  }
}

extension on ReservationCardV2 {
  /// The same actions as [_actions], one per row (narrow phones).
  List<Widget> _stacked(BuildContext context, AppTranslations tr, ResStatus st) {
    final r = reservation;
    Widget cta(String label) => MgCta(label: label, onTap: onTap, size: MgCtaSize.sm48, showMarks: false);
    Widget ghost(String label, VoidCallback onPressed) => MgBtnGhostDark(label: label, onTap: onPressed, height: 48);
    const gap = SizedBox(height: 8);
    switch (st) {
      case ResStatus.aktivni:
        return [
          if (r.sosAllowed)
            Row(children: [Expanded(child: cta(tr.detail)), const SizedBox(width: 8), _SosButton(label: tr.tr('breakdownBtn'))])
          else
            cta(tr.detail),
          if (onEdit != null) ...[gap, ghost(tr.edit, onEdit!)],
        ];
      case ResStatus.nadchazejici:
        return [cta(tr.detail), if (onEdit != null) ...[gap, ghost(tr.edit, onEdit!)]];
      case ResStatus.dokoncene:
        return [cta(tr.tr('rideDetail')), gap, ghost(tr.tr('rateBtn'), onTap)];
      case ResStatus.cancelled:
        return [cta(tr.detail), gap, ghost(tr.tr('restoreBtn'), onRestore ?? onTap)];
    }
  }
}

/// Red SOS on the card strip (`/sos`, only where today's card shows it).
class _SosButton extends StatelessWidget {
  final String label;
  const _SosButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: () => context.push(Routes.sos),
        child: Container(
          height: 48,
          width: 56,
          decoration: BoxDecoration(
            color: MgColors.sos,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: MgColors.sos.withValues(alpha: 0.6), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -10)],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const MgIcon(MgIcons.sos, size: 16, color: MgColors.onDark, stroke: 2.4),
            const SizedBox(height: 2),
            Text('SOS', style: MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark)),
          ]),
        ),
      ),
    );
  }
}
