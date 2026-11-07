import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../catalog_provider.dart';

/// One range slider of the filter, computed by the OLD panel state (same
/// live drag value, same commit rule "end position = no limit") — the v2
/// view only draws it (CB-01).
class FilterRangeModel {
  final String labelKey;
  final String valueLabel;
  final RangeValues values;
  final double min, max;
  final ValueChanged<RangeValues> onDrag;
  final ValueChanged<RangeValues> onDragEnd;
  const FilterRangeModel({
    required this.labelKey,
    required this.valueLabel,
    required this.values,
    required this.min,
    required this.max,
    required this.onDrag,
    required this.onDragEnd,
  });
}

/// Board "Filtr motorek" content (MotoKatalog, light sheet): caps group
/// labels, ink-selected chips (category, ŘP, branch, sort), "Jen dnes
/// volné" switch row and ink range sliders. Every tap calls the SAME
/// setter the old panel calls (passed in by `_MotoFilterPanelState`).
class MotoFilterPanelV2View extends StatelessWidget {
  final CatalogFilter filter;
  final String sort;
  final List<Map<String, dynamic>> branches;
  final List<FilterRangeModel> ranges;
  final List<(String?, String)> licenseOptions;
  final List<(String, String)> sortOptions;
  final bool showReset;
  final VoidCallback onReset;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onLicense;
  final ValueChanged<String?> onBranch;
  final ValueChanged<bool> onToday;
  final ValueChanged<String> onSort;

  const MotoFilterPanelV2View({
    super.key,
    required this.filter,
    required this.sort,
    required this.branches,
    required this.ranges,
    required this.licenseOptions,
    required this.sortOptions,
    required this.showReset,
    required this.onReset,
    required this.onCategory,
    required this.onLicense,
    required this.onBranch,
    required this.onToday,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final branchIds = [for (final b in branches) b['id'] as String?];
    // Same guard as the old dropdown: an unknown branch id reads as "all".
    final branch = branchIds.contains(filter.branch) ? filter.branch : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterLabel(
          tr.tr('homeFilterCategory'),
          trailing: showReset
              ? MgBtnText(label: tr.tr('homeFilterReset'), color: MgColors.err, onTap: onReset)
              : null,
        ),
        _ChipWrap([
          for (final e in MotoCategory.labels.entries)
            MgChoiceChip(
              label: tr.tr(MotoCategory.labelKey(e.key)),
              selected: filter.category == e.key,
              // Same toggle as the old chip: tapping the selected one clears it.
              onTap: () => onCategory(filter.category == e.key ? null : e.key),
            ),
        ]),
        _FilterLabel(tr.tr('homeFilterLicenseGroup')),
        _ChipWrap([
          for (final g in licenseOptions)
            MgChoiceChip(
              label: tr.tr(g.$2),
              selected: filter.licenseGroup == g.$1,
              onTap: () => onLicense(filter.licenseGroup == g.$1 ? null : g.$1),
            ),
        ]),
        _FilterLabel(tr.tr('homeFilterBranch')),
        _ChipWrap([
          MgChoiceChip(
            label: tr.tr('homeFilterAllBranches'),
            selected: branch == null,
            onTap: () => onBranch(null),
          ),
          for (final b in branches)
            MgChoiceChip(
              label: (b['name'] as String?) ?? '',
              selected: branch == b['id'],
              onTap: () => onBranch(b['id'] as String?),
            ),
        ]),
        for (final r in ranges) _InkRange(r),
        const SizedBox(height: MgSpace.s4),
        MgSwitchRow(
          title: tr.tr('homeFilterShowAvailableToday'),
          value: filter.availableTodayOnly,
          onChanged: onToday,
        ),
        const SizedBox(height: MgSpace.s8),
        _ChipWrap([
          for (final o in sortOptions)
            MgChoiceChip(
              label: tr.tr(o.$2),
              selected: sort == o.$1,
              onTap: () => onSort(o.$1),
            ),
        ]),
        const SizedBox(height: MgSpace.s8),
      ],
    );
  }
}

/// Caps group label 11.5/800 `#55705F` (+ optional trailing action).
class _FilterLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _FilterLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: trailing == null ? MgSpace.s16 : MgSpace.s4, bottom: MgSpace.s8),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: MgWordFit(minScale: 0.8, child: Text(text, style: MgType.eyebrow.copyWith(color: MgColors.meta))),
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class _ChipWrap extends StatelessWidget {
  final List<Widget> children;
  const _ChipWrap(this.children);

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: MgSpace.s8, runSpacing: MgSpace.s8, children: children);
}

/// Ink range slider (board): active `#1A2E22` 4 px, inactive well, thumbs
/// 24 white + 1.5 px ink; value right 12.5/800. No divisions (as before).
class _InkRange extends StatelessWidget {
  final FilterRangeModel m;
  const _InkRange(this.m);

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.only(top: MgSpace.s16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: MgWordFit(
              minScale: 0.8,
              child: Text(tr.tr(m.labelKey), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
            ),
          ),
          const SizedBox(width: MgSpace.s8),
          Text(m.valueLabel, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link))),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: MgColors.ink,
            inactiveTrackColor: MgColors.line,
            trackHeight: 4,
            overlayColor: MgColors.inkA(0.10),
            rangeThumbShape: const _InkThumb(),
            rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
          ),
          child: RangeSlider(
            values: m.values,
            min: m.min,
            max: m.max,
            onChanged: m.onDrag,
            onChangeEnd: m.onDragEnd,
          ),
        ),
      ]),
    );
  }
}

/// 24 px white thumb with a 1.5 px ink ring.
class _InkThumb extends RangeSliderThumbShape {
  const _InkThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.square(24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    TextDirection? textDirection,
    required SliderThemeData sliderTheme,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final c = context.canvas;
    c.drawCircle(center + const Offset(0, 1), 12, Paint()..color = MgColors.inkA(0.12));
    c.drawCircle(center, 12, Paint()..color = MgColors.surface);
    c.drawCircle(
      center,
      11.25,
      Paint()
        ..color = MgColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
