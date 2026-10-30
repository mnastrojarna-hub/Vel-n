import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_space.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/widgets/time_dropdown_field.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../booking_models.dart' show PriceBreakdown;
import '../../booking_provider.dart';
import '../../booking_quote.dart';
import '../../price_calculator.dart';
import '../booking_v2_parts.dart';

/// v2 look of `BookingFormTimeSection` (V branch): the SAME
/// `TimeDropdownField`s (hour : minute, 15 min steps) with the SAME
/// callbacks, only themed for v2 inputs. Right under the pickup time the ½
/// row — the ONE place where the 12:00 pickup is chosen (owner 2026-10-22):
/// what this trip saves at 12:00 — the SAME figure the calculator and Home
/// promise ([lateSaving]: standard minus 12:00 total, both with the rank
/// discount; r2 — the gross "Sleva 50 % na 1. den" line stays in the price
/// summary), "Nastavit 12:00" = the same [onTimeChanged] as the dropdown,
/// ✓ once the time is 12:00 or later; the general hint for a 1-day trip.
/// Self-service: plus the info well.
class BookingTimeV2 extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    // Jen termín (poznámka se píše do draftu po znacích).
    final (s, e) = ref.watch(bookingDraftProvider.select((d) => (d.startDate, d.endDate)));
    final moto = ref.watch(bookingMotoProvider);
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final half = moto != null && moto.prices != null && s != null && e != null
        ? lateSaving(quoteFor(moto, s, e, loyalty: loyalty), quoteFor(moto, s, e, pickupTime: '12:00', loyalty: loyalty))
        : 0.0;
    final late = PriceCalculator.isLatePickup(pickupValue);
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
          _HalfOffer(
            on: half > 0 && late,
            text: half <= 0
                ? tr.tr('latePickupHint12')
                : tr.trArgs(late ? 'v2LpFormOnNet' : 'v2LpFormSaveNet', {'amount': bkMoney(half)}),
            setLabel: tr.tr('v2CalcLateSet'),
            onSet: half > 0 && !late ? () => onTimeChanged('12:00') : null,
          ),
          if (selfService) ...[
            const SizedBox(height: 8),
            _InfoWell(text: tr.tr('v2LpSsHint')),
          ],
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

/// What picking up from 12:00 saves: standard minus 12:00 total — the one
/// definition the calculator (`CalcTotalV2`) and Home (`HomeOfferBlockV2`)
/// use too, so the customer sees one number everywhere. Display only.
double lateSaving(PriceBreakdown std, PriceBreakdown at12) {
  final d = std.total - at12.total;
  return d > 0 ? d : 0;
}

class _HalfOffer extends StatelessWidget {
  final String text;

  /// ✓ variant: the chosen time already gets the discount.
  final bool on;
  final String setLabel;

  /// "Nastavit 12:00" (null = no button).
  final VoidCallback? onSet;
  const _HalfOffer({required this.text, required this.on, required this.setLabel, this.onSet});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(10, 8, 12, onSet == null ? 8 : 2),
        decoration: BoxDecoration(
          color: MgColors.tintOk,
          borderRadius: BorderRadius.circular(MgRadius.action),
          border: Border.all(color: MgColors.tintOkBorder, width: on ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (on)
              Semantics(
                label: t(context).tr('v2BkHalfA11y'),
                child: ExcludeSemantics(
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: MgColors.panel, shape: BoxShape.circle),
                    child: MgIcon(MgIcons.check, size: 16, color: MgColors.neon, stroke: 2.6),
                  ),
                ),
              )
            else
              const BkHalfDisc(),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(text,
                    style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk))),
              ),
            ),
          ]),
          if (onSet != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MgBtnText(label: setLabel, icon: MgIcons.clock, onTap: onSet),
            ),
        ]),
      );
}

/// Self-service note (return any time on the last day, kiosk release from
/// 12:00 with the ½ discount).
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
          MgIcon(MgIcons.info, size: 18, color: MgColors.link),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: MgType.small.copyWith(color: MgColors.body2))),
        ]),
      );
}
