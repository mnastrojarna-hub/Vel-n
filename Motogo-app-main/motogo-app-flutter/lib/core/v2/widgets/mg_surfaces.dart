import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/mg_anim.dart';
import '../rank/rank_provider.dart';
import '../rank/rank_tokens.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';

/// White card r16 + `shCard` + 1 px line (light surfaces).
class MgCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;
  final Color color;
  final String? semanticLabel;

  const MgCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MgSpace.card),
    this.margin,
    this.onTap,
    this.radius = MgRadius.card,
    this.color = MgColors.surface,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: child,
    );
    if (onTap != null) {
      card = Semantics(
        button: true,
        label: semanticLabel,
        child: MgPress(onTap: onTap, child: card),
      );
    }
    return card;
  }
}

/// Full-bleed white band (one dense section of a long light screen).
class MgBand extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const MgBand({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: MgSpace.gutter, vertical: MgSpace.s24),
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: MgColors.surface,
        padding: padding,
        child: child,
      );
}

/// Well `#F2F5F3` + 1 px line — tiles, tracks, inputs inside white cards.
class MgWell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const MgWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = MgRadius.button,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: MgColors.line),
        ),
        child: child,
      );
}

/// The ONE dark hero block of a window (`gDark`, r20, `shDark`, 1 px neon .25
/// border). [rankAura] tints the first gradient stop with the rank aura
/// (success / pending heroes, ticket); off = brand dark.
class MgDarkHero extends ConsumerWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool rankAura;
  final RankTokens? rank;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const MgDarkHero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: MgSpace.heroH, vertical: MgSpace.heroV),
    this.rankAura = false,
    this.rank,
    this.radius = MgRadius.hero,
    this.margin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Gradient g = rankAura
        ? MgGradients.hero((rank ?? ref.watch<RankTokens>(rankTokensProvider)).aura)
        : MgGradients.dark;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: g,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MgColors.neonA(0.25)),
        boxShadow: MgShadows.dark,
      ),
      child: DefaultTextStyle.merge(style: const TextStyle(color: MgColors.onDark), child: child),
    );
  }
}

/// Checked / positive state only ("Zaplaceno", "zdarma s rankem").
class MgTintOk extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const MgTintOk({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = MgRadius.button,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: MgColors.tintOk,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: MgColors.tintOkBorder),
        ),
        child: DefaultTextStyle.merge(style: const TextStyle(color: MgColors.onTintOk), child: child),
      );
}

/// At most ONE per screen: mint feature gradient, or the offer box (dashed
/// look approximated by a 1 px solid `#37CF63` border).
class MgTintFeature extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool offer;
  final double radius;
  const MgTintFeature({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MgSpace.card),
    this.offer = false,
    this.radius = MgRadius.card,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: offer ? MgGradients.offer : MgGradients.tintFeature,
          borderRadius: BorderRadius.circular(radius),
          border: offer ? Border.all(color: MgColors.tintOkBorder) : null,
        ),
        child: child,
      );
}
