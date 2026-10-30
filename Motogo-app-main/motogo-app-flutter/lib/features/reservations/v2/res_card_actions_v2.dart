import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../reservation_models.dart';
import 'res_fit_v2.dart';
import 'res_status_v2.dart';

/// The ONE card of the list with the dark rank stub (V22 R5.2 — one dark
/// block per window; board `.ls-s` on one card, `.ls-s.lt` on the rest):
/// the card that needs action first — unpaid / payment being verified,
/// else the running rental, else the nearest upcoming one; without any of
/// them the first card. Only the look depends on it.
String? resPrimaryCardId(List<Reservation> list, PendingBooking? pending) {
  if (list.isEmpty) return null;
  for (final r in list) {
    if (resPayFlag(r, pending) != ResPayFlag.none) return r.id;
  }
  for (final r in list) {
    if (r.displayStatus == ResStatus.aktivni) return r.id;
  }
  Reservation? next;
  for (final r in list) {
    if (r.displayStatus == ResStatus.nadchazejici && (next == null || r.startDate.isBefore(next.startDate))) next = r;
  }
  return (next ?? list.first).id;
}

/// Action strip of `ReservationCardV2` with the SAME actions per status as
/// today's `ReservationCard` (Detail · Upravit · SOS / Detail jízdy ·
/// Hodnotit / Detail · Obnovit). [primary]: dark rank stub with the glowing
/// CTA + glass ghost; otherwise a white stub under a perforation with
/// `btnGhostLight` + `btnText` (R5.8). SOS stays red in both.
class ResCardActionsV2 extends ConsumerWidget {
  final Reservation reservation;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onRestore;
  final bool primary;

  const ResCardActionsV2({
    super.key,
    required this.reservation,
    required this.onTap,
    this.onEdit,
    this.onRestore,
    this.primary = true,
  });

  static final _textStyle = MgType.small.copyWith(fontWeight: FontWeight.w800);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final st = reservation.displayStatus;
    final aura = ref.watch(rankTokensProvider).aura;
    // Úzký telefon (320 dp): tlačítka pod sebou na celou šířku, ať se
    // „Wiederherstellen" / „Редагувати" nikdy nedělí uprostřed slova.
    final strip = LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 300 && _fits(context, tr, st, c.maxWidth)) return Row(children: _row(tr, st));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _stacked(tr, st));
    });
    if (primary) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(gradient: MgGradients.hero(aura)),
        child: strip,
      );
    }
    return ColoredBox(
      color: MgColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CustomPaint(size: Size.fromHeight(2), painter: _PerforationPainter()),
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: strip),
      ]),
    );
  }

  /// Main action: the rank CTA on the dark stub, `btnGhostLight` on white.
  Widget _main(String label, {bool expand = true}) => primary
      ? MgCta(label: label, onTap: onTap, size: MgCtaSize.sm48, showMarks: false, expand: expand)
      : MgBtnGhostLight(label: label, onTap: onTap, height: 48, expand: expand);

  /// Second action: glass ghost on dark, `btnText` on white.
  Widget _second(String label, VoidCallback onPressed) =>
      primary ? MgBtnGhostDark(label: label, onTap: onPressed, height: 48) : MgBtnText(label: label, onTap: onPressed);

  List<Widget> _row(AppTranslations tr, ResStatus st) {
    final r = reservation;
    Widget half(Widget w) => Expanded(child: w);
    const gap = SizedBox(width: 8);
    switch (st) {
      case ResStatus.aktivni:
        // Se SOS: Detail jen na šířku popisku, SOS jako ikona (48 px) — ať se
        // „Upravit" vejde celé i v delších jazycích (de „Bearbeiten").
        if (r.sosAllowed) {
          return [
            _main(tr.detail, expand: false),
            if (onEdit != null) ...[gap, half(_second(tr.edit, onEdit!))] else const Spacer(),
            gap,
            _SosButton(label: tr.tr('breakdownBtn')),
          ];
        }
        return [half(_main(tr.detail)), if (onEdit != null) ...[gap, half(_second(tr.edit, onEdit!))]];
      case ResStatus.nadchazejici:
        return [half(_main(tr.detail)), if (onEdit != null) ...[gap, half(_second(tr.edit, onEdit!))]];
      case ResStatus.dokoncene:
        return [half(_main(tr.tr('rideDetail'))), gap, half(_second(tr.tr('rateBtn'), onTap))];
      case ResStatus.cancelled:
        return [half(_main(tr.detail)), gap, half(_second(tr.tr('restoreBtn'), onRestore ?? onTap))];
    }
  }

  /// true when [_row] fits one row of [width] with every word whole (the
  /// buttons' `MgWordFit` scales labels to 80 % at most): de
  /// „Wiederherstellen" / uk „Редагувати" at 360 dp with large text → stack.
  bool _fits(BuildContext context, AppTranslations tr, ResStatus st, double width) {
    final cta = MgType.ctaCompact.copyWith(letterSpacing: 0.3);
    const ctaPad = 27.0, ghostPad = 35.0, textPad = 32.0, gap = 8.0;
    bool mainFits(String l, double w) => primary
        ? resWordsFit(context, l.toUpperCase(), cta, w - ctaPad, minScale: 0.8)
        : resWordsFit(context, l, MgType.button, w - ghostPad, minScale: 0.8);
    bool secondFits(String l, double w) => primary
        ? resWordsFit(context, l, MgType.button, w - ghostPad, minScale: 0.8)
        : resWordsFit(context, l, _textStyle, w - textPad, minScale: 0.8);
    final half = (width - gap) / 2;
    switch (st) {
      case ResStatus.aktivni:
        if (reservation.sosAllowed) {
          // Detail na šířku popisku (jeden řádek), Upravit zbytek, SOS 56 dp.
          final detailW = primary
              ? resLineWidth(context, tr.detail.toUpperCase(), cta) + ctaPad
              : resLineWidth(context, tr.detail, MgType.button) + ghostPad;
          if (onEdit == null) return detailW + gap + 56 <= width;
          return secondFits(tr.edit, width - detailW - gap - gap - 56);
        }
        return mainFits(tr.detail, onEdit == null ? width : half) && (onEdit == null || secondFits(tr.edit, half));
      case ResStatus.nadchazejici:
        return mainFits(tr.detail, onEdit == null ? width : half) && (onEdit == null || secondFits(tr.edit, half));
      case ResStatus.dokoncene:
        return mainFits(tr.tr('rideDetail'), half) && secondFits(tr.tr('rateBtn'), half);
      case ResStatus.cancelled:
        return mainFits(tr.detail, half) && secondFits(tr.tr('restoreBtn'), half);
    }
  }

  /// The same actions as [_row], one per row (narrow phones).
  List<Widget> _stacked(AppTranslations tr, ResStatus st) {
    const gap = SizedBox(height: 8);
    switch (st) {
      case ResStatus.aktivni:
        return [
          if (reservation.sosAllowed)
            Row(children: [Expanded(child: _main(tr.detail)), const SizedBox(width: 8), _SosButton(label: tr.tr('breakdownBtn'))])
          else
            _main(tr.detail),
          if (onEdit != null) ...[gap, _second(tr.edit, onEdit!)],
        ];
      case ResStatus.nadchazejici:
        return [_main(tr.detail), if (onEdit != null) ...[gap, _second(tr.edit, onEdit!)]];
      case ResStatus.dokoncene:
        return [_main(tr.tr('rideDetail')), gap, _second(tr.tr('rateBtn'), onTap)];
      case ResStatus.cancelled:
        return [_main(tr.detail), gap, _second(tr.tr('restoreBtn'), onRestore ?? onTap)];
    }
  }
}

/// Ticket perforation over the white stub (board `.ls-s.lt::before`:
/// 6 px dashes, 5 px gaps, `#CBD8D1`).
class _PerforationPainter extends CustomPainter {
  const _PerforationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFCBD8D1);
    for (var x = 0.0; x < size.width; x += 11) {
      canvas.drawRect(Rect.fromLTWH(x, 0, (size.width - x).clamp(0, 6).toDouble(), size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PerforationPainter oldDelegate) => false;
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
