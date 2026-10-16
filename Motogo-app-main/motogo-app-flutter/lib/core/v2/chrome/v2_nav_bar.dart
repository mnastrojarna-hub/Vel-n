import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../rank/rank_frame.dart';
import '../rank/rank_provider.dart';
import '../rank/rank_tokens.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'v2_nav_fit.dart';

/// The v2 bottom nav (`shared/nav.html`): Domů · Motorky · Rezervace ·
/// Trasy · Profil on night glass (.96, no blur — low-end Android), top r20,
/// neon hairline, 64 + safe area. Active tab = icon in the CTA label colour
/// on a 52×30 rank pill (liquid move 300 ms); PROFIL = avatar in the rank
/// ring + arc. Labels pass the no-overlap fit ([v2NavFit]) in every language
/// — never ellipsized / wrapped / scaled. Dumb widget: [onTap] gets the tab
/// index (the shell maps it to `onShellTabTap`).
class V2NavBar extends ConsumerWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;

  /// Unread messages count on PROFIL (0 = none).
  final int profileBadge;

  /// Red dot on REZERVACE (a booking needs action).
  final bool bookingsNeedAction;
  final RankTokens? rank;
  final double? arcPct;

  const V2NavBar({
    super.key,
    required this.activeIndex,
    required this.onTap,
    this.profileBadge = 0,
    this.bookingsNeedAction = false,
    this.rank,
    this.arcPct,
  });

  static const tabKeys = ['v2TabHome', 'v2TabBikes', 'v2TabBookings', 'v2TabRoutes', 'v2TabProfile'];
  static const shortKeys = [null, null, 'v2TabBookingsShort', 'v2TabRoutesShort', null];
  static const icons = [MgIcons.home, MgIcons.moto, MgIcons.calendarCheck, MgIcons.route, null];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final RankTokens r = rank ?? ref.watch(rankTokensProvider);
    final double? arc = arcPct ?? ref.watch(rankArcPctProvider);
    final full = [for (final k in tabKeys) tr.tr(k)];
    final short = [for (final k in shortKeys) k == null ? null : tr.tr(k)];
    final base = DefaultTextStyle.of(context).style.merge(MgType.navActive);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final reduced = MgMotion.reduced(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: tr.tr('v2NavAria'),
      child: Container(
        decoration: BoxDecoration(
          color: MgColors.night.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: MgColors.black(0.16), blurRadius: 24, offset: const Offset(0, -4))],
        ),
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(builder: (context, c) {
            final width = c.maxWidth;
            final col = width / 5;
            final fit = v2NavFitCached(
              full: full,
              short: short,
              width: width,
              base: base,
              scale: MediaQuery.textScalerOf(context).scale(11) / 11,
            );
            final index = activeIndex.clamp(0, 4);
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 24,
                right: 24,
                top: 0,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [MgColors.neonA(0), MgColors.neonA(0.38), MgColors.neonA(0)]),
                  ),
                ),
              ),
              if (activeIndex >= 0)
                AnimatedPositioned(
                  duration: reduced ? Duration.zero : MgMotion.thumb,
                  curve: MgMotion.spring,
                  left: index * col + (col - 52) / 2,
                  top: 7,
                  width: 52,
                  height: 30,
                  child: _Pill(rank: r, trigger: index, reduced: reduced),
                ),
              Row(children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: _Tab(
                      label: fit.labels[i],
                      fullLabel: full[i],
                      px: fit.px,
                      base: base,
                      active: i == activeIndex,
                      icon: icons[i],
                      rank: r,
                      arcPct: arc,
                      dot: i == 2 && bookingsNeedAction,
                      count: i == 4 ? profileBadge : 0,
                      tooltip: fit.compromised && (fit.shortened[i] || fit.rung > 1),
                      onTap: () => onTap(i),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final RankTokens rank;
  final int trigger;
  final bool reduced;
  const _Pill({required this.rank, required this.trigger, required this.reduced});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: rank.edgeGradient,
        boxShadow: rank.softGlow(),
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: rank.ctaGradient,
        ),
      ),
    );
    if (reduced) return pill;
    // Liquid stretch: scaleX 1 → 1.45 → 1 while the pill travels.
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: 0, end: 1),
      duration: MgMotion.thumb,
      builder: (_, t, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(1 + 0.45 * math.sin(math.pi * t), 1 - 0.14 * math.sin(math.pi * t), 1),
        child: child,
      ),
      child: pill,
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final String fullLabel;
  final double px;
  final TextStyle base;
  final bool active;
  final String? icon;
  final RankTokens rank;
  final double? arcPct;
  final bool dot;
  final int count;
  final bool tooltip;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.fullLabel,
    required this.px,
    required this.base,
    required this.active,
    required this.icon,
    required this.rank,
    required this.arcPct,
    required this.dot,
    required this.count,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final iconColor = active ? rank.ctaLabel : MgColors.onDarkMeta;
    final visual = icon != null
        ? MgIcon(icon!, size: 24, color: iconColor)
        : RankFrame(
            rank: rank,
            size: 30,
            circle: true,
            ringWidth: 2.5,
            arcPct: arcPct,
            arcGap: 5,
            showLevel: false,
            showGlyph: false,
            showMarks: false,
            glow: false,
            child: const ColoredBox(
              color: MgColors.panel,
              child: Center(child: MgIcon(MgIcons.person, size: 15, color: MgColors.onDarkBody, stroke: 2.2)),
            ),
          );
    var sem = fullLabel;
    if (count > 0) sem += ', ${tr.trArgs('v2NavUnread', {'n': count})}';
    if (dot) sem += ', ${tr.tr('v2NavNeedsAction')}';
    Widget tab = MgPress(
      scale: 0.92,
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Column(children: [
          const SizedBox(height: 7),
          SizedBox(
            width: 52,
            height: 30,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              visual,
              if (dot)
                Positioned(
                  top: 2,
                  right: 9,
                  child: MgPop(
                    playOnMount: true,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: MgColors.sosDot,
                        shape: BoxShape.circle,
                        border: Border.all(color: MgColors.night, width: 2),
                      ),
                    ),
                  ),
                ),
              if (count > 0)
                Positioned(
                  top: -2,
                  right: 2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MgColors.sos,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: MgColors.night, width: 2),
                    ),
                    child: Text(count > 9 ? '9+' : '$count',
                        style: MgType.tab(MgType.micro.copyWith(
                            fontWeight: FontWeight.w800, height: 1, color: MgColors.onDark))),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textScaler: TextScaler.noScaling,
            style: base.copyWith(
              fontSize: px,
              height: 14 / 11,
              fontWeight: active ? FontWeight.w800 : FontWeight.w700,
              color: active ? MgColors.onDark : MgColors.onDarkSecondary,
            ),
          ),
        ]),
      ),
    );
    if (tooltip) {
      tab = Tooltip(
        message: fullLabel,
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.longPress,
        child: tab,
      );
    }
    return Semantics(
      button: true,
      selected: active,
      label: sem,
      excludeSemantics: true,
      onTap: onTap,
      child: tab,
    );
  }
}
