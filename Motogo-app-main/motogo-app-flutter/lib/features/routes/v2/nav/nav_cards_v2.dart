import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import 'nav_hud_v2.dart';

BoxDecoration _card({Color? border}) => BoxDecoration(
      color: MgColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border ?? MgColors.line, width: border == null ? 1 : 1.5),
      boxShadow: MgShadows.card,
    );

/// "Dojel jsi na místo" (board TrasaDetail, V21 T11): eyebrow + name, ✕
/// 44 (does NOT confirm the stop — old onClose), the "Místo objeveno! ·
/// celkem 13" chip with ONE neon ring (pop 300 + ring 700, static under
/// reduced motion), compact rank CTA "DALŠÍ: …" (no loop) = the manual
/// confirmation, ★ (rate the place) and ☰ (stops) discs.
class StopReachedCardV2 extends StatelessWidget {
  final String name;
  final String? visitLine;
  final bool firstVisit;
  final String? nextLabel;
  final VoidCallback onNext;
  final VoidCallback onChoose;
  final VoidCallback onClose;
  final VoidCallback? onRate;
  const StopReachedCardV2({
    super.key,
    required this.name,
    required this.visitLine,
    required this.firstVisit,
    required this.nextLabel,
    required this.onNext,
    required this.onChoose,
    required this.onClose,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: _card(),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const MgIconTileDark(MgIcons.pin, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.tr('navStopReached').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink)),
              ),
            ]),
          ),
          navDiscV2(MgIcons.close, tr.tr('close'), onClose, close: true),
        ]),
        if (visitLine != null) ...[
          const SizedBox(height: 8),
          _DiscoveredChip(text: visitLine!, ring: firstVisit),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: MgCta(
              label: nextLabel != null ? tr.tr('navNextStopBtn').replaceFirst('{name}', nextLabel!) : mgNavNoEmoji(tr.tr('routeNavArrived')),
              size: MgCtaSize.xs44,
              leadingIcon: MgIcons.navigate,
              showMarks: false,
              onTap: onNext,
            ),
          ),
          if (onRate != null) ...[const SizedBox(width: 8), navDiscV2(MgIcons.starFilled, tr.tr('routeReviewAdd'), onRate, color: MgColors.star)],
          const SizedBox(width: 8),
          navDiscV2(MgIcons.list, tr.tr('navStopsTitle'), onChoose),
        ]),
      ]),
    );
  }
}

/// Dark chip "✓ Místo objeveno! · celkem 13" — one neon ring when it is a
/// first visit (V21 T11, the only motion of the screen; static reduced).
class _DiscoveredChip extends StatelessWidget {
  final String text;
  final bool ring;
  const _DiscoveredChip({required this.text, required this.ring});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: MgColors.panel, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        MgIcon(ring ? MgIcons.star : MgIcons.check, size: 15, color: MgColors.neon),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neon))),
      ]),
    );
    if (!ring || MgMotion.reduced(context)) return chip;
    return MgPop(
      playOnMount: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MgMotion.ripple,
        curve: MgMotion.out,
        builder: (_, v, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BoxShadow(color: MgColors.neonA(0.55 * (1 - v)), spreadRadius: 10 * v)],
          ),
          child: child,
        ),
        child: chip,
      ),
    );
  }
}

/// "Trasa dokončena!" (board): dark flag tile, title, ✕ 44 and the rank
/// CTA "★ OHODNOTIT TRASU" (→ the reviews sheet) or "Uložit do Mých tras"
/// for a custom ride — the old onRate / onSave / onClose.
class RouteDoneCardV2 extends StatelessWidget {
  final bool canRate;
  final bool canSave;
  final VoidCallback onRate;
  final VoidCallback onSave;
  final VoidCallback onClose;
  const RouteDoneCardV2({
    super.key,
    required this.canRate,
    required this.canSave,
    required this.onRate,
    required this.onSave,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: _card(),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const MgIconTileDark(MgIcons.flag, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: MgWordFit(child: Text(tr.tr('navRouteDone'), style: MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
            ),
          ),
          navDiscV2(MgIcons.close, tr.tr('close'), onClose, close: true),
        ]),
        const SizedBox(height: 10),
        if (canRate)
          MgCta(label: tr.tr('navRateRoute'), leadingIcon: MgIcons.starFilled, size: MgCtaSize.sm48, showMarks: false, onTap: onRate),
        if (canRate && canSave) const SizedBox(height: 8),
        if (canSave)
          MgCta(label: tr.tr('navSaveRoute'), leadingIcon: MgIcons.bookmark, size: MgCtaSize.sm48, showMarks: false, onTap: onSave),
      ]),
    );
  }
}

/// "Křižovatka — kam dál?" (board): white card with a green edge, two
/// option tiles — the side of the next stop is the ink tile with "Příští".
class NavForkHintV2 extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool nextIsLeft;
  final VoidCallback? onTap;
  const NavForkHintV2({super.key, required this.leftLabel, required this.rightLabel, required this.nextIsLeft, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget side(String label, bool next, bool left) {
      final fg = next ? MgColors.onDark : MgColors.ink;
      final arrow = Transform.flip(flipX: left, child: MgIcon(MgIcons.arrowRight, size: 20, color: next ? MgColors.neon : MgColors.link));
      return Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: next ? MgColors.panel : MgColors.well,
            borderRadius: BorderRadius.circular(14),
            border: next ? null : Border.all(color: MgColors.line),
          ),
          child: Row(children: [
            if (left) ...[arrow, const SizedBox(width: 6)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
                if (next) Text(tr.tr('routeNavNext'), style: MgType.meta.copyWith(color: MgColors.neon)),
              ]),
            ),
            if (!left) ...[const SizedBox(width: 6), arrow],
          ]),
        ),
      );
    }

    return Semantics(
      button: onTap != null,
      label: '${tr.tr('navForkTitle')} $leftLabel / $rightLabel',
      child: MgPress(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: _card(border: MgColors.neonLo),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const MgIcon(MgIcons.route, size: 16, color: MgColors.link),
              const SizedBox(width: 6),
              Flexible(child: Text(tr.tr('navForkTitle'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
            ]),
            const SizedBox(height: 8),
            Row(children: [side(leftLabel, nextIsLeft, true), const SizedBox(width: 8), side(rightLabel, !nextIsLeft, false)]),
          ]),
        ),
      ),
    );
  }
}
