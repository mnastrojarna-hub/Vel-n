import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'places_parts_v2.dart' show TrasyChipRailV2;

/// One active filter of the Trasy list as a removable chip (5.0.1): what it
/// says and how its ✕ drops exactly that filter (the screen's own setters).
class RtFilterChipItem {
  final String label;
  final VoidCallback onRemove;
  const RtFilterChipItem(this.label, this.onRemove);
}

/// Toolbar of the Trasy list (5.0.1, owner: "bílý, nevýrazný" chips →
/// clear controls): Filtry (dark, neon when on, with the count) · Řadit: …
/// · Mapa tras — and, while anything is on, the loud green card "Filtry
/// zapnuté (n)" with every filter as a chip with ✕ and "Zrušit vše" (the
/// bike filter's look). The same actions as before: the filter sheet, the
/// sort sheet, the routes map, the old "Zrušit" (= "Zrušit vše").
class RoutesToolbarV2 extends StatelessWidget {
  final int activeCount;
  final String sortLabel;
  final bool sortOn;
  final VoidCallback onFilter;
  final VoidCallback onSort;
  final VoidCallback onMap;
  final VoidCallback onClear;
  final List<RtFilterChipItem> chips;

  const RoutesToolbarV2({
    super.key,
    required this.activeCount,
    required this.sortLabel,
    required this.sortOn,
    required this.onFilter,
    required this.onSort,
    required this.onMap,
    required this.onClear,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final on = activeCount > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TrasyChipRailV2(children: [
        _ToolButton(
          key: const ValueKey('rt-tool-filter'),
          label: tr.tr('routesFilter'),
          icon: MgIcons.filter,
          style: on ? _ToolStyle.neon : _ToolStyle.dark,
          count: on ? activeCount : null,
          onTap: onFilter,
        ),
        _ToolButton(
          key: const ValueKey('rt-tool-sort'),
          label: sortLabel,
          icon: MgIcons.sort,
          style: sortOn ? _ToolStyle.on : _ToolStyle.outline,
          caret: true,
          onTap: onSort,
        ),
        _ToolButton(
          key: const ValueKey('rt-tool-map'),
          label: tr.tr('routesMapBtn'),
          icon: MgIcons.map,
          style: _ToolStyle.outline,
          onTap: onMap,
        ),
      ]),
      if (on)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: RoutesActiveFiltersV2(count: activeCount, chips: chips, onClear: onClear),
        ),
    ]);
  }
}

enum _ToolStyle { dark, neon, outline, on }

/// A 44 px toolbar control with a strong fill / a 1.5 px ink outline.
class _ToolButton extends StatelessWidget {
  final String label;
  final String icon;
  final _ToolStyle style;
  final int? count;
  final bool caret;
  final VoidCallback onTap;
  const _ToolButton({
    super.key,
    required this.label,
    required this.icon,
    required this.style,
    required this.onTap,
    this.count,
    this.caret = false,
  });

  @override
  Widget build(BuildContext context) {
    final (Color? bg, Gradient? grad, Color border, Color fg, Color ic) = switch (style) {
      _ToolStyle.dark => (MgColors.ink, null, MgColors.ink, MgColors.onDark, MgColors.neon),
      _ToolStyle.neon => (null, MgGradients.neon, MgColors.link, MgColors.onNeon, MgColors.onNeon),
      _ToolStyle.on => (MgColors.tintOk, null, MgColors.link, MgColors.onTintOk, MgColors.link),
      _ToolStyle.outline => (MgColors.surface, null, MgColors.ink, MgColors.ink, MgColors.link),
    };
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: style == _ToolStyle.neon || style == _ToolStyle.on,
        label: count == null ? label : '$label, $count',
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: AnimatedContainer(
            duration: MgMotion.of(context, MgMotion.color),
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bg,
              gradient: grad,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border, width: 1.5),
              boxShadow: style == _ToolStyle.neon
                  ? const [BoxShadow(color: Color(0x5537CF63), blurRadius: 12, offset: Offset(0, 3))]
                  : style == _ToolStyle.dark
                      ? MgShadows.card
                      : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MgIcon(icon, size: 17, color: ic),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w < 360 ? 200 : w - 150),
                child: MgWordFit(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg, height: 1.25)),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: MgColors.onNeon, borderRadius: BorderRadius.circular(999)),
                  child: Text('$count',
                      textAlign: TextAlign.center,
                      style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.neon))),
                ),
              ],
              if (caret) ...[const SizedBox(width: 4), MgIcon(MgIcons.chevronDown, size: 16, color: fg)],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The loud "Filtry zapnuté (n)" card: neon badge, "Nevidíš všechny
/// trasy", the chips (✕ drops one) and "Zrušit vše".
class RoutesActiveFiltersV2 extends StatelessWidget {
  final int count;
  final List<RtFilterChipItem> chips;
  final VoidCallback onClear;
  const RoutesActiveFiltersV2({super.key, required this.count, required this.chips, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final title = tr.trArgs('rtListFltOn', {'n': count});
    final clear = tr.tr('rtListFltClear');
    return Container(
      key: const ValueKey('rt-filters-on'),
      padding: const EdgeInsets.fromLTRB(MgSpace.card - 2, 12, MgSpace.card - 2, 10),
      decoration: BoxDecoration(
        color: MgColors.tintOk,
        borderRadius: BorderRadius.circular(MgRadius.card),
        border: Border.all(color: MgColors.link, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          header: true,
          label: '$title. ${tr.tr('rtListFltHint')}',
          excludeSemantics: true,
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: MgGradients.neon,
                border: Border.all(color: MgColors.link, width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x5537CF63), blurRadius: 12, offset: Offset(0, 3))],
              ),
              child: const Center(child: MgIcon(MgIcons.filter, size: 20, color: MgColors.onNeon)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                MgWordFit(
                  minScale: 0.75,
                  child: Text(title, maxLines: 1, style: MgType.section.copyWith(color: MgColors.link)),
                ),
                const SizedBox(height: 2),
                Text(tr.tr('rtListFltHint'),
                    style: MgType.small.copyWith(color: MgColors.onTintOk, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final c in chips) _RemoveChip(item: c, label: tr.trArgs('rtListFltRemove', {'f': c.label})),
          _ClearAll(label: clear, onTap: onClear),
        ]),
      ]),
    );
  }
}

class _RemoveChip extends StatelessWidget {
  final RtFilterChipItem item;
  final String label;
  const _RemoveChip({required this.item, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: item.onRemove,
        child: MgPress(
          onTap: item.onRemove,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
            decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
              ),
              const SizedBox(width: 6),
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: MgColors.neon),
                child: const Center(child: MgIcon(MgIcons.close, size: 13, stroke: 2.6, color: MgColors.onNeon)),
              ),
            ]),
          ),
        ),
      );
}

class _ClearAll extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ClearAll({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          key: const ValueKey('rt-filters-clear'),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.link, width: 1.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const MgIcon(MgIcons.close, size: 16, color: MgColors.link),
              const SizedBox(width: 5),
              Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
            ]),
          ),
        ),
      );
}
