import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import 'rt_sheet_rows_v2.dart';
import 'rt_sheet_v2.dart';

/// One range of the Trasy filter (length / riding time): the screen's
/// bounds, current values, labels and its linked `setDist` / `setDur`.
class RtRange {
  final double min;
  final double max;
  final RangeValues values;
  final RangeLabels labels;
  final String valueText;
  final ValueChanged<RangeValues> onChanged;
  const RtRange({
    required this.min,
    required this.max,
    required this.values,
    required this.labels,
    required this.valueText,
    required this.onChanged,
  });
}

/// v2 look of Trasy → "Filtrovat trasy" (board TrasyHub `sht.filt`):
/// states first, length + riding time (linked, as today), "počítat i cestu
/// od mé polohy" and the pinned "Zobrazit (n)". State, the live count and
/// all callbacks stay in `routes_screen.dart`.
class RoutesFilterSheetV2 extends StatelessWidget {
  final List<RtOpt> countriesTop;
  final List<RtOpt> countriesRest;
  final bool moreCountries;
  final VoidCallback onMoreCountries;
  final RtRange? dist;
  final RtRange? dur;
  final RtOpt? approach;
  final int count;
  final VoidCallback onApply;
  final VoidCallback onClear;
  const RoutesFilterSheetV2({
    super.key,
    required this.countriesTop,
    required this.countriesRest,
    required this.moreCountries,
    required this.onMoreCountries,
    required this.dist,
    required this.dur,
    required this.approach,
    required this.count,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final hasCountries = countriesTop.isNotEmpty || countriesRest.isNotEmpty;
    return RtSheetV2(
      title: tr.tr('routesFilterTitle'),
      clearLabel: tr.tr('routesFilterClear'),
      onClear: onClear,
      footer: MgBtnInk(label: '${tr.tr('routesFilterApply')} ($count)', onTap: onApply),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hasCountries) ...[
          RtSectionV2(tr.tr('routesFilterCountry'), top: 8),
          RtCountriesV2(top: countriesTop, rest: countriesRest, open: moreCountries, onMore: onMoreCountries),
        ],
        if (dist != null) ...[
          RtSectionV2(tr.tr('routesFilterDistance'), value: dist!.valueText, top: hasCountries ? 20 : 8),
          _RtSlider(dist!),
        ],
        if (dur != null) ...[
          RtSectionV2(tr.tr('routesFilterDuration'), value: dur!.valueText, top: 12),
          _RtSlider(dur!),
          Text(tr.tr('routesFilterLinkedHint'), style: MgType.small.copyWith(color: MgColors.meta)),
        ],
        if (approach != null) ...[
          const SizedBox(height: 16),
          RtChipV2(approach!),
        ],
      ]),
    );
  }
}

/// v2 look of Trasy → "Řadit": radio rows with icon tiles; a tap picks
/// and closes (the screen's existing callback).
class RoutesSortSheetV2 extends StatelessWidget {
  final List<RtOpt> options;
  const RoutesSortSheetV2({super.key, required this.options});

  @override
  Widget build(BuildContext context) => RtSheetV2(
        title: t(context).tr('sortTitle'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final o in options) Padding(padding: const EdgeInsets.only(bottom: 4), child: RtSortRowV2(o)),
        ]),
      );
}

class _RtSlider extends StatelessWidget {
  final RtRange r;
  const _RtSlider(this.r);

  @override
  Widget build(BuildContext context) => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: MgColors.link,
          inactiveTrackColor: MgColors.line,
          overlayColor: MgColors.neon.withValues(alpha: 0.28),
          rangeThumbShape: const _RtThumb(),
          valueIndicatorColor: MgColors.ink,
          valueIndicatorTextStyle: MgType.small.copyWith(color: MgColors.onDark, fontWeight: FontWeight.w800),
        ),
        child: RangeSlider(
          min: r.min,
          max: r.max,
          values: r.values,
          labels: r.labels,
          onChanged: r.onChanged,
        ),
      );
}

/// Board `.rng i`: white 24 px thumb, 2 px green ring, soft shadow.
class _RtThumb extends RangeSliderThumbShape {
  const _RtThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final c = context.canvas;
    final path = Path()..addOval(Rect.fromCircle(center: center, radius: 12));
    c.drawShadow(path, MgColors.night, 2, false);
    c.drawCircle(center, 12, Paint()..color = MgColors.surface);
    c.drawCircle(
      center,
      11,
      Paint()
        ..color = MgColors.neonLo
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
