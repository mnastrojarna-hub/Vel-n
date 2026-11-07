import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/mg_club_emblem.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'home_fit.dart';

/// Tier icon of a rank (emblem / rail) — moved to core (`mgClubTierIcon`).
String clubTierIcon(RankTier t) => mgClubTierIcon(t);

/// 44 px tier emblem (→ ranks screen) — now `MgClubEmblem` in core.
typedef ClubEmblem = MgClubEmblem;

/// Tier progress bar — now `MgClubTierBar` in core.
typedef ClubTierBar = MgClubTierBar;

/// One segment of [ClubTierBar] — now `mgClubTierSegment` in core.
BoxDecoration clubTierSegment(RankTokens rank, {required bool lit, required bool next}) =>
    mgClubTierSegment(rank, lit: lit, next: next);

/// Privilege tile on the well (big value or icon + label).
class ClubPerk extends StatelessWidget {
  final String? big;
  final String? icon;
  final String label;
  final bool locked;
  const ClubPerk({super.key, this.big, this.icon, required this.label, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.well,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.line, style: BorderStyle.solid),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (big != null)
          Text(big!, style: MgType.tab(MgType.h2.copyWith(fontWeight: FontWeight.w900, color: MgColors.link)))
        else if (icon != null)
          MgIcon(icon!, size: 22, color: locked ? MgColors.lead : MgColors.link),
        const SizedBox(height: 4),
        MgWordFit(
          minScale: 0.8,
          child: Text(label, style: _perkLabel),
        ),
      ]),
    );
  }
}

const _perkLabel = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.3, color: MgColors.ink);

/// The two privilege tiles: side by side when every word of both labels
/// fits half the width (at the current text size), else stacked full width
/// — "Passagiersuitrusting" never splits on a narrow phone / large text.
class ClubPerkPair extends StatelessWidget {
  final ClubPerk first;
  final ClubPerk second;
  const ClubPerkPair({super.key, required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final half = (c.maxWidth - 10) / 2 - 24 - 2;
      bool fits(String text) => homeWordsFitIn(context, text, _perkLabel, half);

      if (c.maxWidth >= 300 && fits(first.label) && fits(second.label)) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ]),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, const SizedBox(height: 10), second]);
    });
  }
}

/// The 5 leagues as dark mini discs carrying the tier material (passed /
/// current ring / locked). Names in semantics + long-press tooltip.
class ClubTierRail extends StatelessWidget {
  final int current;
  const ClubTierRail({super.key, required this.current});

  static const _from = [1, 6, 10, 17, 20];
  static const _pts = [0, 10, 18, 32, 38];

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Row(children: [
      for (var i = 0; i < 5; i++) ...[
        if (i > 0)
          Expanded(
            child: Container(height: 2, color: i <= current ? MgColors.link : MgColors.line),
          ),
        _disc(tr, i),
      ],
    ]);
  }

  Widget _disc(AppTranslations tr, int i) {
    final r = rankTokensForLevel(_from[i]);
    final name = RankCopy.tierName(tr, r.tier);
    final state = i < current
        ? tr.tr('v2HomeClubPassed')
        : i == current
            ? tr.tr('v2HomeClubHere')
            : tr.trArgs('v2HomeClubFrom', {'n': _pts[i], 'points': RankCopy.points(tr, _pts[i])});
    final locked = i > current;
    return Tooltip(
      message: '$name · $state',
      child: Semantics(
        label: '$name, $state',
        excludeSemantics: true,
        child: MgReveal(
          index: i,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MgColors.panel,
              boxShadow: i == current
                  ? const [BoxShadow(color: MgColors.surface, spreadRadius: 2), BoxShadow(color: MgColors.link, spreadRadius: 4)]
                  : [BoxShadow(color: MgColors.inkA(0.14), spreadRadius: 1)],
            ),
            padding: const EdgeInsets.all(8),
            child: Opacity(
              opacity: locked ? 0.55 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: r.ctaGradient),
                child: Center(
                  child: MgIcon(locked ? MgIcons.lock : clubTierIcon(r.tier), size: 13, color: r.ctaLabel),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
