import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/price_calculator.dart' show branchLat, branchLng;
import '../reservation_models.dart';
import '../widgets/res_location_row.dart';

/// "Kdy a kde" (white card): pickup + return through `ResLocationRow` with
/// the SAME address / GPS / fallback arguments as today's detail (navigation
/// ALWAYS by GPS, main-branch coordinates when the branch has none).
class ResWhenWhereV2 extends StatelessWidget {
  final Reservation res;
  final String? branchFullAddress;
  const ResWhenWhereV2({super.key, required this.res, required this.branchFullAddress});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final pickupWhen = res.pickupAllDayLegacy
        ? '${tripShortDate(tr, res.startDate)} · ${tr.tr('ssPickupAnyTime')}'
        : res.pickupHm != null
            ? '${tripShortDate(tr, res.startDate)} · ${res.pickupHm}'
            : tripShortDate(tr, res.startDate);
    return MgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgEyebrow(tr.tr('v2ResWhenWhere'), dark: false),
        ResLocationRow(
          label: tr.pickup,
          when: pickupWhen,
          isDelivery: res.pickupMethod == 'delivery',
          address: res.pickupMethod == 'delivery' ? res.pickupAddress : branchFullAddress,
          lat: res.pickupMethod == 'delivery' ? res.pickupLat : (res.branchLat ?? branchLat),
          lng: res.pickupMethod == 'delivery' ? res.pickupLng : (res.branchLng ?? branchLng),
          fallbackAddress: res.pickupMethod == 'delivery' ? res.pickupAddress : branchFullAddress,
        ),
        ResLocationRow(
          label: tr.returnLabel,
          when: tripShortDate(tr, res.endDate),
          isDelivery: res.returnMethod == 'delivery',
          address: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
          lat: res.returnMethod == 'delivery' ? res.returnLat : (res.branchLat ?? branchLat),
          lng: res.returnMethod == 'delivery' ? res.returnLng : (res.branchLng ?? branchLng),
          fallbackAddress: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
        ),
      ]),
    );
  }
}

/// "Výbava" (white card): sizes chosen at booking (rider + passenger) and
/// "own gear" — straight from the reservation fields. Hidden when the
/// booking has none.
class ResGearV2 extends StatelessWidget {
  final Reservation res;
  const ResGearV2({super.key, required this.res});

  static bool _has(String? s) => (s ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rider = <(String, String, String)>[
      if (_has(res.helmetSize)) (MgIcons.helmet, tr.tr('helmet'), res.helmetSize!),
      if (_has(res.jacketSize)) (MgIcons.jacket, tr.tr('jacket'), res.jacketSize!),
      if (_has(res.pantsSize)) (MgIcons.pants, tr.tr('pants'), res.pantsSize!),
      if (_has(res.glovesSize)) (MgIcons.glove, tr.tr('gloves'), res.glovesSize!),
      if (_has(res.bootsSize)) (MgIcons.boot, tr.tr('driverBootsLabel'), res.bootsSize!),
    ];
    final passenger = <(String, String, String)>[
      if (_has(res.passengerHelmetSize)) (MgIcons.helmet, tr.tr('helmet'), res.passengerHelmetSize!),
      if (_has(res.passengerJacketSize)) (MgIcons.jacket, tr.tr('jacket'), res.passengerJacketSize!),
      if (_has(res.passengerPantsSize)) (MgIcons.pants, tr.tr('pants'), res.passengerPantsSize!),
      if (_has(res.passengerGlovesSize)) (MgIcons.glove, tr.tr('gloves'), res.passengerGlovesSize!),
      if (_has(res.passengerBootsSize)) (MgIcons.boot, tr.tr('bootsPassengerLabel'), res.passengerBootsSize!),
    ];
    final own = res.ownGear == true;
    if (rider.isEmpty && passenger.isEmpty && !own) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgEyebrow(tr.tr('v2ResGear'), dark: false),
          if (own) ...[
            const SizedBox(height: 12),
            Row(children: [
              const MgIcon(MgIcons.checkCircle, size: 18, color: MgColors.link),
              const SizedBox(width: 8),
              Expanded(child: Text(tr.tr('ownGear'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink))),
            ]),
          ],
          if (rider.isNotEmpty) _group(null, rider),
          if (passenger.isNotEmpty) _group(tr.tr('passengerGearLabel'), passenger),
        ]),
      ),
    );
  }

  Widget _group(String? title, List<(String, String, String)> items) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Text(title, style: MgType.meta.copyWith(color: MgColors.meta)),
            const SizedBox(height: 6),
          ],
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: MgColors.well,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.line),
                ),
                // Název se při nedostatku místa (fr na 320 dp) zalomí v mezeře.
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MgIcon(g.$1, size: 16, color: MgColors.link),
                  const SizedBox(width: 6),
                  Flexible(child: MgWordFit(child: Text(g.$2, style: MgType.small.copyWith(color: MgColors.body2)))),
                  const SizedBox(width: 4),
                  Text(g.$3, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                ]),
              ),
          ]),
        ]),
      );
}
