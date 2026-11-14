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
import '../shell/shell_nav_map.dart' show v2TabReselectProvider;
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'v2_nav_fit.dart';
import 'v2_nav_fx.dart';

/// The v2 bottom nav (`shared/nav.html`): Domů · Motorky · Rezervace ·
/// Trasy · Profil on night glass (.96, no blur — low-end Android), top r20,
/// neon hairline, 64 + safe area. Active tab (v5.0.1, owner "víc svítivě
/// zelené, jako to původní"): icon + label in dark on a filled brand-neon
/// pill with a green halo ([V2NavPill]: liquid move 300 ms, slow breathing
/// halo after it lands), the original elastic pop of the icon
/// ([V2NavBounce]) and a filled icon; PROFIL = avatar in the rank ring + arc
/// on a night disc while active (the loyalty rank shows there, not on the
/// pill). Labels pass the no-overlap fit ([v2NavFit]) in every language
/// — never ellipsized / wrapped (only an active label too tight for its
/// pill steps down, at most 12 %). Dumb widget: [onTap] gets the tab
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

  /// Filled twins shown on the active pill (the original menu: outlined at
  /// rest, filled when active); the motorcycle is one filled glyph already.
  static const activeIcons = <IconData?>[
    Icons.home_rounded,
    null,
    Icons.event_available_rounded,
    null,
    null,
  ];

  /// Active pill width for tab [i] of label widths [w] (the active one
  /// measured w900) in columns [col]: col − 6 (52…76), at least its label +
  /// 6 px a side, but 1 px clear of the neighbouring labels and 6 px from
  /// the bar edges (German at 320); a label that still lacks its 6 px is
  /// stepped down ([activePx]).
  static double pillWidth(List<double> w, int i, double col) {
    var half = math.max((col - 6).clamp(52.0, 76.0) / 2, w[i] / 2 + 6);
    final left = i == 0 ? col / 2 - 6 : col - w[i - 1] / 2 - 1;
    final right = i == w.length - 1 ? col / 2 - 6 : col - w[i + 1] / 2 - 1;
    half = math.min(half, math.min(left, right));
    return 2 * math.max(half, w[i] * minActiveScale / 2 + 6);
  }

  /// Smallest step-down of the active label (keeps it the strongest word).
  static const double minActiveScale = 0.88;

  /// Font size of the active label [w] wide at [px] on a [pill] wide pill:
  /// [px], or smaller so 6 px of neon stay on each side.
  static double activePx(double w, double pill, double px) =>
      w + 12 <= pill || w <= 0 ? px : px * ((pill - 12) / w).clamp(minActiveScale, 1.0);

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
    final reselect = ref.watch(v2TabReselectProvider);

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
            final measure = v2NavMeasure(base);
            final heavy = v2NavMeasure(base, weight: FontWeight.w900);
            final widths = [
              for (var i = 0; i < 5; i++) (i == index ? heavy : measure)(fit.labels[i], fit.px),
            ];
            final pw = pillWidth(widths, index, col);
            final apx = activePx(widths[index], pw, fit.px);
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
                  left: index * col + (col - pw) / 2,
                  top: 4,
                  width: pw,
                  height: 56,
                  // Own layer: the breathing halo repaints only the pill.
                  child: RepaintBoundary(child: V2NavPill(trigger: index, reduced: reduced)),
                ),
              Row(children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: _Tab(
                      label: fit.labels[i],
                      fullLabel: full[i],
                      px: i == activeIndex ? apx : fit.px,
                      base: base,
                      active: i == activeIndex,
                      icon: icons[i],
                      activeIcon: activeIcons[i],
                      rank: r,
                      arcPct: arc,
                      dot: i == 2 && bookingsNeedAction,
                      count: i == 4 ? profileBadge : 0,
                      tooltip: fit.compromised && (fit.shortened[i] || fit.rung > 1),
                      nudge: reselect.$1 == i ? reselect.$2 : 0,
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

/// Key of the night disc behind the Profil avatar on the active pill.
const ValueKey<String> kV2NavRankBacking = ValueKey('v2-nav-rank-backing');

class _Tab extends StatelessWidget {
  final String label;
  final String fullLabel;
  final double px;
  final TextStyle base;
  final bool active;
  final String? icon;
  final IconData? activeIcon;
  final RankTokens rank;
  final double? arcPct;
  final bool dot;
  final int count;
  final bool tooltip;
  final VoidCallback onTap;

  /// Re-tap sequence of this tab (0 = none): a 3 px upward nudge.
  final int nudge;

  const _Tab({
    required this.label,
    required this.fullLabel,
    required this.px,
    required this.base,
    required this.active,
    required this.icon,
    this.activeIcon,
    required this.rank,
    required this.arcPct,
    required this.dot,
    required this.count,
    required this.tooltip,
    required this.onTap,
    this.nudge = 0,
  });

  /// The rank ring + arc keep their night backing on the neon pill (the
  /// green ranks would vanish into it): a 38 px night disc behind them.
  /// (Overflows the 30 px icon row on purpose.)
  Widget _onPill(Widget frame) => !active
      ? frame
      : OverflowBox(
          minWidth: 38,
          maxWidth: 38,
          minHeight: 38,
          maxHeight: 38,
          child: Container(
            key: kV2NavRankBacking,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: MgColors.night, shape: BoxShape.circle),
            child: SizedBox.square(dimension: 30, child: frame),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final iconColor = active ? MgColors.onNeon : MgColors.onDarkSecondary;
    final visual = icon != null
        ? (active && activeIcon != null
            ? Icon(activeIcon, size: 24, color: iconColor)
            : MgIcon(icon!, size: 24, color: iconColor))
        : _onPill(RankFrame(
            rank: rank,
            size: 30,
            circle: true,
            ringWidth: 2.5,
            arcPct: arcPct,
            // On the neon pill the arc moves in onto a night disc.
            arcGap: active ? 2 : 5,
            showLevel: false,
            showGlyph: false,
            showMarks: false,
            glow: false,
            child: const ColoredBox(
              color: MgColors.panel,
              child: Center(child: MgIcon(MgIcons.person, size: 15, color: MgColors.onDarkBody, stroke: 2.2)),
            ),
          ));
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
              V2NavNudge(trigger: nudge, child: V2NavBounce(active: active, child: visual)),
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
              // Right of the avatar's head (never over the person glyph).
              if (count > 0)
                Positioned(
                  top: -3,
                  left: 31,
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
          AnimatedDefaultTextStyle(
            duration: MgMotion.of(context, MgMotion.color),
            style: base.copyWith(
              fontSize: px,
              height: 14 / 11,
              fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              color: active ? MgColors.onNeon : MgColors.onDarkLead,
            ),
            // Centred on the tab even when wider than its column (German).
            child: SizedBox(
              height: px * 14 / 11,
              child: OverflowBox(
                maxWidth: double.infinity,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  textScaler: TextScaler.noScaling,
                ),
              ),
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
