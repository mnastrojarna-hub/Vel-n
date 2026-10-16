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
  final RankTokens rank;
  final VoidCallback onTap;
  const _Tab({
    required this.icon,
    required this.title,
    required this.sub,
    required this.selected,
    required this.rank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? rank.ctaLabel : MgColors.onDark;
    final subFg = selected ? rank.ctaLabel.withValues(alpha: 0.78) : MgColors.onDarkMeta;
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
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? rank.ctaLabel.withValues(alpha: 0.14) : MgColors.neonA(0.14),
                ),
                child: Center(child: MgIcon(icon, size: 16, color: selected ? fg : MgColors.neon)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 2,
                      softWrap: true,
                      style: MgType.ctaCompact.copyWith(color: fg, letterSpacing: -0.1, height: 1.15)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 2,
                      softWrap: true,
                      style: MgType.micro.copyWith(fontWeight: FontWeight.w600, color: subFg)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
