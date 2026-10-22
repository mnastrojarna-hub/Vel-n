import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'catalog_fit.dart';
import 'catalog_mode.dart';

/// "Najít motorku · Filtr nabídky" | "Spočítat cenu · Volné dny a cena"
/// (board `.km`, web `f_mode_*`): rank-material thumb sliding 300 ms; both
/// tabs share one height (titles wrap to 2 lines, never ellipsize).
class CatalogModeSwitchV2 extends ConsumerWidget {
  final CatalogMode mode;
  final ValueChanged<CatalogMode> onChanged;
  const CatalogModeSwitchV2({super.key, required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final RankTokens r = ref.watch(rankTokensProvider);
    final calc = mode == CatalogMode.calc;
    return Semantics(
      container: true,
      label: tr.tr('v2CatModeAria'),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: MgColors.white(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.neonA(0.22)),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 4) / 2;
          // Narrow tab (320 dp, large text, long words like "Розрахувати"):
          // the icon goes above the texts so the title gets the full tab
          // width — a word is never split, the sub never cut.
          final base = DefaultTextStyle.of(context).style;
          final side = w - 16 - 38;
          final titleW = [tr.tr('v2CatModeFind'), tr.tr('v2CatModeCalc')]
              .map((x) => catWordWidth(context, x, base.merge(_Tab.titleStyle)))
              .reduce((a, b) => a > b ? a : b);
          final subW = [tr.tr('v2CatModeFindSub'), tr.tr('v2CatModeCalcSub')]
              .map((x) => catWordWidth(context, x, base.merge(_Tab.subStyle)))
              .reduce((a, b) => a > b ? a : b);
          final stacked = titleW * 0.9 > side || subW > side;
          return Stack(children: [
            AnimatedPositioned(
              duration: MgMotion.of(context, MgMotion.thumb),
              curve: MgMotion.spring,
              left: calc ? w + 4 : 0,
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(
                  gradient: r.ctaGradient,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: r.hex.withValues(alpha: 0.5)),
                  boxShadow: r.softGlow(blur: 16, dy: 6),
                ),
              ),
            ),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _Tab(
                    icon: MgIcons.search,
                    title: tr.tr('v2CatModeFind'),
                    sub: tr.tr('v2CatModeFindSub'),
                    selected: !calc,
                    stacked: stacked,
                    rank: r,
                    onTap: () => onChanged(CatalogMode.find),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _Tab(
                    icon: MgIcons.calc,
                    title: tr.tr('v2CatModeCalc'),
                    sub: tr.tr('v2CatModeCalcSub'),
                    selected: calc,
                    stacked: stacked,
                    rank: r,
                    onTap: () => onChanged(CatalogMode.calc),
                  ),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String icon;
  final String title;
  final String sub;
  final bool selected;
  final bool stacked;
  final RankTokens rank;
  final VoidCallback onTap;
  const _Tab({
    required this.icon,
    required this.title,
    required this.sub,
    required this.selected,
    required this.stacked,
    required this.rank,
    required this.onTap,
  });

  static final titleStyle = MgType.ctaCompact.copyWith(letterSpacing: -0.1, height: 1.15);
  static final subStyle = MgType.micro.copyWith(fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final fg = selected ? rank.ctaLabel : MgColors.onDark;
    final subFg = selected ? rank.ctaLabel.withValues(alpha: 0.78) : MgColors.onDarkMeta;
    final box = stacked ? 26.0 : 30.0;
    final iconBox = Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? rank.ctaLabel.withValues(alpha: 0.14) : MgColors.neonA(0.14),
      ),
      child: Center(child: MgIcon(icon, size: stacked ? 14 : 16, color: selected ? fg : MgColors.neon)),
    );
    final texts = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      MgWordFit(
        minScale: 0.75,
        child: Text(title, maxLines: 2, softWrap: true, style: titleStyle.copyWith(color: fg)),
      ),
      const SizedBox(height: 2),
      MgWordFit(
        minScale: 0.85,
        child: Text(sub, maxLines: 2, softWrap: true, style: subStyle.copyWith(color: subFg)),
      ),
    ]);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $sub',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: selected ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: stacked
                ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    iconBox,
                    const SizedBox(height: 6),
                    texts,
                  ])
                : Row(children: [iconBox, const SizedBox(width: 8), Expanded(child: texts)]),
          ),
        ),
      ),
    );
  }
}
