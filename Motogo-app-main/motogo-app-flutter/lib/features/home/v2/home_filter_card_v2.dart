import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/widgets/availability_calendar.dart';
import '../../catalog/widgets/moto_filter_panel.dart';

/// Domů v2 filter = the old `MotoFilterPanel(showDates: true)` in the v2
/// look (owner 2026-11-07 "jen upgrade vzhledu"): COLLAPSED by default, the
/// header (title, active count, "Resetovat", chevron) opens it; collapsed it
/// shows the chosen branch. Open: "TERMÍN" + the existing calendar (its v2
/// look), then the existing panel content (`MotoFilterPanel(embedded)` =
/// the v2 view with the panel's own setters). Every write is the one the old
/// panel makes — `catalogFilterProvider` / `catalogSortProvider`.
class HomeFilterCardV2 extends ConsumerStatefulWidget {
  const HomeFilterCardV2({super.key});

  @override
  ConsumerState<HomeFilterCardV2> createState() => _HomeFilterCardV2State();
}

class _HomeFilterCardV2State extends ConsumerState<HomeFilterCardV2> {
  bool _open = false;

  CatalogFilter get _f => ref.read(catalogFilterProvider);
  void _set(CatalogFilter next) => ref.read(catalogFilterProvider.notifier).state = next;

  /// The old panel's reset on Domů (dates belong to this panel there).
  void _reset() {
    _set(const CatalogFilter());
    ref.read(catalogSortProvider.notifier).state = 'default';
  }

  String _dateLabel(AppTranslations tr, CatalogFilter f) {
    final s = f.startDate, e = f.endDate;
    if (s == null || e == null) return tr.tr('homeFilterDatesAny');
    String d(DateTime x) => '${x.day}. ${x.month}.';
    return s == e ? d(s) : '${d(s)} – ${d(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final filter = ref.watch(catalogFilterProvider);
    final active = filter.activeCount;
    final title = tr.tr('homeFilterTitle');

    final header = Semantics(
      button: true,
      expanded: _open,
      label: active > 0 ? '$title, $active' : title,
      excludeSemantics: true,
      child: MgPress(
        key: const ValueKey('home-filter-toggle'),
        scale: 0.99,
        onTap: () => setState(() => _open = !_open),
        child: Container(
          color: Colors.transparent,
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(children: [
            const MgIcon(MgIcons.filter, size: 20, color: MgColors.link),
            const SizedBox(width: 8),
            Flexible(
              child: MgWordFit(minScale: 0.8, child: Text(title, style: MgType.title.copyWith(color: MgColors.ink))),
            ),
            if (active > 0) ...[
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('home-filter-count'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
                child: Text('$active', style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
              ),
            ],
            const Spacer(),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: MgMotion.of(context, MgMotion.tab),
              curve: MgMotion.emphasized,
              child: const MgIcon(MgIcons.chevronDown, size: 22, color: MgColors.lead),
            ),
          ]),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: MgCard(
        key: const ValueKey('home-filter-card'),
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: header),
            // „Resetovat" v hlavičce jako u starého panelu; otevřený panel má
            // vlastní (u Kategorie) — stejná akce.
            if (active > 0 && !_open)
              MgBtnText(key: const ValueKey('home-filter-reset'), label: tr.tr('homeFilterReset'), color: MgColors.err, onTap: _reset),
          ]),
          if (!_open) _BranchLine(onTap: () => setState(() => _open = true)),
          MgAnimatedSize(
            duration: MgMotion.of(context, MgMotion.morph),
            curve: MgMotion.emphasized,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 12),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${tr.tr('homeFilterDates')} '),
                        TextSpan(
                          text: _dateLabel(tr, filter),
                          style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                        ),
                      ]),
                      key: const ValueKey('home-filter-dates'),
                      style: MgType.eyebrow.copyWith(color: MgColors.meta),
                    ),
                    const SizedBox(height: 8),
                    AvailabilityCalendar(
                      selectedStart: filter.startDate,
                      selectedEnd: filter.endDate,
                      onRangeSelected: (start, end) => _set(_f.copyWith(startDate: () => start, endDate: () => end)),
                      onReset: () => _set(_f.copyWith(startDate: () => null, endDate: () => null)),
                    ),
                    const SizedBox(height: 16),
                    const MotoFilterPanel(showDates: true, embedded: true),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// The chosen branch under the collapsed header (old `FilterBranchChip`).
class _BranchLine extends ConsumerWidget {
  /// Opens the panel (old: a tap on the chip opened it).
  final VoidCallback onTap;
  const _BranchLine({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(catalogFilterProvider.select((f) => f.branch));
    if (id == null) return const SizedBox.shrink();
    String? name;
    for (final b in ref.watch(branchesProvider)) {
      if (b['id'] == id) name = b['name'] as String?;
    }
    if (name == null) return const SizedBox.shrink();
    return MgPress(
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const ValueKey('home-filter-branch'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: MgColors.tintOk,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.tintOkBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.pin, size: 15, color: MgColors.onTintOk),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${t(context).tr('branchPrefix')}: $name',
                  maxLines: 2,
                  style: MgType.meta.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk)),
            ),
          ]),
        ),
      ),
    ));
  }
}
