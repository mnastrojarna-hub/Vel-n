import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/banner_provider.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/shell/mg_origin_chip.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../loyalty/loyalty_provider.dart';
import '../catalog_provider.dart';
import 'catalog_mode.dart';
import 'catalog_mode_switch_v2.dart';
import 'catalog_price.dart';
import 'catalog_text.dart';

/// Dark rank header of the v2 Motorky tab (board `.hd`): title + count,
/// rank chip, view toggle, mode switch, date pill (+ ✕), filter / branch
/// chips and the CMS banner as its last line (the v2 shell does not draw
/// the banner on `/search`). Display + callbacks only — the screen owns
/// every write (same writes as the old search screen).
class MotorkyHeaderV2 extends ConsumerWidget {
  final CatalogMode mode;
  final ValueChanged<CatalogMode> onMode;

  /// Count of shown bikes (null = still loading / failed).
  final int? count;
  final bool grid;
  final ValueChanged<bool> onGrid;
  final VoidCallback onOpenDates;
  final VoidCallback onClearDates;
  final VoidCallback onOpenFilters;
  final ValueChanged<String?> onBranch;

  const MotorkyHeaderV2({
    super.key,
    required this.mode,
    required this.onMode,
    required this.count,
    required this.grid,
    required this.onGrid,
    required this.onOpenDates,
    required this.onClearDates,
    required this.onOpenFilters,
    required this.onBranch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final filter = ref.watch(catalogFilterProvider);
    final branches = ref.watch(branchesProvider);
    final banner = ref.watch(bannerProvider).valueOrNull;
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final find = mode == CatalogMode.find;
    final s = filter.startDate, e = filter.endDate;
    final hasDates = s != null && e != null;
    return MgRankHero(
      ambientKey: 'motorky',
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // „‹ Domů / Pobočka" po skoku z jiné záložky (V22 §6.2).
        const MgOriginChip(tab: 1),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                Semantics(
                  header: true,
                  child: Text(tr.tr('v2TabBikes'), style: MgType.h2.copyWith(color: MgColors.onDark, height: 1)),
                ),
                if (count != null)
                  MgBump(
                    trigger: count,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: MgColors.neonA(0.16), borderRadius: BorderRadius.circular(999)),
                      child: Text(catCount(tr, count!), style: MgType.tab(MgType.micro.copyWith(color: MgColors.neonText))),
                    ),
                  ),
              ]),
              if (loyalty != null && loyalty.level >= 1) ...[
                const SizedBox(height: 8),
                MgRankChip(label: RankCopy.chip(tr, RankCopy.name(tr, loyalty.level, loyalty.rankName), loyalty.percent)),
              ],
            ]),
          ),
          if (find) _ViewToggle(grid: grid, onGrid: onGrid),
        ]),
        const SizedBox(height: 12),
        CatalogModeSwitchV2(mode: mode, onChanged: onMode),
        catAnimatedSize(context, !find
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 12),
                  _DatePill(
                    label: hasDates ? catRange(tr, s, e) : tr.tr('v2CatDateEmpty'),
                    hint: hasDates ? catDays(tr, catDayCount(s, e)) : tr.tr('v2CatDateEmptySub'),
                    filled: hasDates,
                    onTap: onOpenDates,
                    onClear: hasDates ? onClearDates : null,
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(children: [
                      _Chip(
                        label: tr.tr('v2CatFilters'),
                        icon: MgIcons.filter,
                        badge: filter.activeCount,
                        semantic: tr.trArgs('v2CatFiltersAria', {'n': filter.activeCount}),
                        onTap: onOpenFilters,
                      ),
                      if (branches.length > 1) ...[
                        const SizedBox(width: 8),
                        _Chip(label: tr.tr('homeFilterAllBranches'), selected: filter.branch == null, onTap: () => onBranch(null)),
                        for (final b in branches) ...[
                          const SizedBox(width: 8),
                          _Chip(
                            label: b['name'] as String,
                            icon: MgIcons.pin,
                            selected: filter.branch == b['id'],
                            onTap: () => onBranch(filter.branch == b['id'] ? null : b['id'] as String),
                          ),
                        ],
                      ],
                    ]),
                  ),
                ]),
        ),
        if (banner != null && banner.enabled && banner.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: false,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgIcon(MgIcons.info, size: 18, color: MgColors.neon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(banner.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.neonText)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final bool grid;
  final ValueChanged<bool> onGrid;
  const _ViewToggle({required this.grid, required this.onGrid});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget b(bool g, String d, String label) {
      final on = grid == g;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        onTap: () => onGrid(g),
        child: MgPress(
          onTap: on ? null : () => onGrid(g),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: on ? MgColors.neon : const Color(0x00000000),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: CatPathIcon(d, color: on ? MgColors.onNeon : MgColors.onDarkLead)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: MgColors.white(0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        b(false, CatPathIcon.fullCards, tr.tr('v2CatViewFull')),
        const SizedBox(width: 2),
        b(true, CatPathIcon.grid, tr.tr('v2CatViewGrid')),
      ]),
    );
  }
}

class _DatePill extends StatelessWidget {
  final String label;
  final String hint;
  final bool filled;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _DatePill({required this.label, required this.hint, required this.filled, required this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: filled ? MgColors.neonA(0.55) : MgColors.white(0.25), width: 1.5),
      ),
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: true,
            label: '$label, $hint',
            excludeSemantics: true,
            onTap: onTap,
            child: MgPress(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(children: [
                  MgIcon(MgIcons.calendarCheck, size: 20, color: MgColors.neon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark, height: 1.2))),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: MgColors.neonA(0.14), borderRadius: BorderRadius.circular(999)),
                    child: Text(hint, style: MgType.tab(MgType.meta.copyWith(color: MgColors.neonText))),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (onClear != null)
          Semantics(
            button: true,
            label: tr.tr('v2CatDateClear'),
            excludeSemantics: true,
            onTap: onClear,
            child: MgPress(
              onTap: onClear,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(child: MgIcon(MgIcons.close, size: 20, color: MgColors.onDarkLead)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String? icon;
  final bool selected;
  final int badge;
  final String? semantic;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap, this.icon, this.selected = false, this.badge = 0, this.semantic});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? MgColors.onNeon : MgColors.onDark;
    return Semantics(
      button: true,
      selected: selected,
      label: semantic ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? MgColors.neon : MgColors.white(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? MgColors.neon : MgColors.white(0.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[MgIcon(icon!, size: 16, color: selected ? fg : MgColors.neon), const SizedBox(width: 6)],
            Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg, height: 1)),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: MgColors.neon, borderRadius: BorderRadius.circular(999)),
                child: Text('$badge',
                    textAlign: TextAlign.center, style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.onNeon))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
