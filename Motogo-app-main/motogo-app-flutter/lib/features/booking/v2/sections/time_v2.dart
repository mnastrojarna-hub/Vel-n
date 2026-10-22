import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_space.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/widgets/time_dropdown_field.dart';
import '../booking_v2_parts.dart';

/// v2 look of `BookingFormTimeSection` (V branch): the SAME
/// `TimeDropdownField`s (hour : minute, 15 min steps) with the SAME
/// callbacks, only themed for v2 inputs; the late-pickup hint becomes the
/// ½ offer row, the self-service hint an info well (informal copy).
class BookingTimeV2 extends StatelessWidget {
  final String pickupValue;
  final String returnValue;
  final bool showPickup;
  final bool showReturn;
  final bool selfService;
  final void Function(String) onTimeChanged;
  final void Function(String) onReturnTimeChanged;

  const BookingTimeV2({
    super.key,
    required this.pickupValue,
    required this.returnValue,
    required this.showPickup,
    required this.showReturn,
    required this.selfService,
    required this.onTimeChanged,
    required this.onReturnTimeChanged,
  });

  /// v2 inputs (white, 1.5 px `lineInput`, focus 2 px `#0D6E0D`, 15/800
  /// tabular value) for the dropdowns, which take their borders and text
  /// style from the theme.
  static ThemeData inputTheme(ThemeData base) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(MgRadius.action),
          borderSide: BorderSide(color: c, width: w),
        );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleMedium: (base.textTheme.titleMedium ?? const TextStyle())
            .merge(MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: MgColors.surface,
        border: b(MgColors.lineInput, 1.5),
        enabledBorder: b(MgColors.lineInput, 1.5),
        focusedBorder: b(MgColors.focusLight, 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget dropdown(String value, void Function(String) onChanged) => Theme(
          data: inputTheme(Theme.of(context)),
          child: TimeDropdownField(value: value, onChanged: onChanged),
        );
    return BkCard(
      icon: MgIcons.clock,
      title: tr.tr(showPickup ? 'v2BkPickupTime' : 'v2BkReturnTime'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showPickup) ...[
          dropdown(pickupValue, onTimeChanged),
          const SizedBox(height: 10),
          if (selfService)
            _InfoWell(text: tr.tr('v2BkSsPickupHint'))
          else
            _HalfOffer(text: tr.tr('latePickupHint12')),
        ],
        if (showPickup && showReturn) ...[
          const SizedBox(height: 16),
          BkLabel(tr.tr('v2BkReturnTime')),
        ],
        if (showReturn) dropdown(returnValue, onReturnTimeChanged),
      ]),
    );
  }
}

class _HalfOffer extends StatelessWidget {
  final String text;
  const _HalfOffer({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: MgColors.tintOk,
          borderRadius: BorderRadius.circular(MgRadius.action),
          border: Border.all(color: MgColors.tintOkBorder),
        ),
        child: Row(children: [
          const BkHalfDisc(),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk))),
        ]),
      );
}

class _InfoWell extends StatelessWidget {
  final String text;
  const _InfoWell({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(MgRadius.action),
          border: Border.all(color: MgColors.line),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const BkHalfDisc(),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: MgType.small.copyWith(color: MgColors.body2))),
        ]),
      );
}
