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

  /// Shown on the sort pill (the sort glyph says "Řadit"); null = [sortLabel].
  final String? sortValue;
  final bool sortOn;
  final VoidCallback onFilter;
  final VoidCallback onSort;
  final VoidCallback onMap;
  final VoidCallback onClear;
  final List<RtFilterChipItem> chips;

  /// A filter that HIDES routes is on (countries, length, search) — only
  /// then the card says "Nevidíš všechny trasy" (sort / approach reorder).
  final bool narrowing;

  const RoutesToolbarV2({
    super.key,
    required this.activeCount,
    required this.sortLabel,
    this.sortValue,
    required this.sortOn,
    required this.onFilter,
    required this.onSort,
    required this.onMap,
    required this.onClear,
    this.chips = const [],
    this.narrowing = true,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final on = activeCount > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // Nothing scrolls off the edge: one row when the labels fit, else the
      // sort pill takes its own row (whole label, never cut). The map (also
      // in the header) is an icon square.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(builder: (context, c) {
          final need = _ToolButton.widthOf(context, tr.tr('routesFilter'), extra: on ? 29 : 0) +
              _ToolButton.widthOf(context, sortValue ?? sortLabel, extra: 20) +
              44;
          // A badge must not push the sort pill to a row of its own (FV-04):
          // first the two labelled buttons tighten their side padding.
          final dense = need > c.maxWidth + 12;
          final one = need - (dense ? 16 : 0) <= c.maxWidth + 12;
          final tight = dense && one;
          final filter = _ToolButton(
            dense: tight,
            key: const ValueKey('rt-tool-filter'),
            label: tr.tr('routesFilter'),
            icon: MgIcons.filter,
            style: on ? _ToolStyle.neon : _ToolStyle.dark,
            count: on ? activeCount : null,
            onTap: onFilter,
          );
          final sort = _ToolButton(
            dense: tight,
            key: const ValueKey('rt-tool-sort'),
            label: sortValue ?? sortLabel,
            semantic: sortLabel,
            icon: MgIcons.sort,
            style: sortOn ? _ToolStyle.on : _ToolStyle.outline,
            caret: true,
            onTap: onSort,
          );
          final map = _ToolButton(
            key: const ValueKey('rt-tool-map'),
            label: tr.tr('routesMapBtn'),
            icon: MgIcons.map,
            style: _ToolStyle.outline,
            iconOnly: true,
            onTap: onMap,
          );
          // A little over still fits one row: the sort label scales down (MgWordFit).
          if (one) {
            return Row(children: [
              filter,
              Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: sort)),
              map
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [filter, const Spacer(), map]),
            const SizedBox(height: 8),
            sort,
          ]);
        }),
      ),
      if (on)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: RoutesActiveFiltersV2(count: activeCount, chips: chips, onClear: onClear, narrowing: narrowing),
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

  /// A 44 px square with the glyph only (the label is the semantics).
  final bool iconOnly;

  /// Screen-reader label when it differs from [label].
  final String? semantic;
  final VoidCallback onTap;
  const _ToolButton({
    super.key,
    required this.label,
    required this.icon,
    required this.style,
    required this.onTap,
    this.count,
    this.caret = false,
    this.iconOnly = false,
    this.semantic,
    this.dense = false,
  });

  /// 10 px side padding instead of 14 (a tight one-row toolbar).
  final bool dense;

  static TextStyle get _labelStyle => MgType.small.copyWith(fontWeight: FontWeight.w800, height: 1.25);

  /// The full width of a labelled control ([extra] = badge / caret).
  static double widthOf(BuildContext context, String label, {double extra = 0}) {
    final tp = TextPainter(
      // The inherited family (the theme's font), as the Text resolves it.
      text: TextSpan(text: label, style: DefaultTextStyle.of(context).style.merge(_labelStyle)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return 14 + 17 + 7 + w + extra + 14 + 3 + 8 + 1;
  }

  @override
  Widget build(BuildContext context) {
    final (Color? bg, Gradient? grad, Color border, Color fg, Color ic) = switch (style) {
      _ToolStyle.dark => (MgColors.ink, null, MgColors.ink, MgColors.onDark, MgColors.neon),
      _ToolStyle.neon => (null, MgGradients.neon, MgColors.link, MgColors.onNeon, MgColors.onNeon),
      _ToolStyle.on => (MgColors.tintOk, null, MgColors.link, MgColors.onTintOk, MgColors.link),
      _ToolStyle.outline => (MgColors.surface, null, MgColors.ink, MgColors.ink, MgColors.link),
    };
    return Padding(
      padding: EdgeInsets.only(right: iconOnly ? 0 : 8),
      child: Semantics(
        button: true,
        selected: style == _ToolStyle.neon || style == _ToolStyle.on,
        label: count == null ? (semantic ?? label) : '${semantic ?? label}, $count',
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: AnimatedContainer(
            duration: MgMotion.of(context, MgMotion.color),
            constraints: BoxConstraints(minHeight: 44, minWidth: iconOnly ? 44 : 0),
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : (dense ? 10 : 14)),
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
            child: iconOnly
                ? SizedBox(width: 41, height: 41, child: Center(child: MgIcon(icon, size: 20, color: ic)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    MgIcon(icon, size: 17, color: ic),
                    const SizedBox(width: 7),
                    Flexible(
                      child: MgWordFit(
                        minScale: dense ? 0.75 : 0.85,
                        fitLines: dense ? 1 : null,
                        child: Text(label, maxLines: 2, style: _labelStyle.copyWith(color: fg)),
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
  final bool narrowing;
  const RoutesActiveFiltersV2(
      {super.key, required this.count, required this.chips, required this.onClear, this.narrowing = true});

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
          label: narrowing ? '$title. ${tr.tr('rtListFltHint')}' : title,
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
                if (narrowing) ...[
                  const SizedBox(height: 2),
                  Text(tr.tr('rtListFltHint'),
                      style: MgType.small.copyWith(color: MgColors.onTintOk, fontWeight: FontWeight.w700)),
                ],
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
