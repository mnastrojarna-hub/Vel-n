import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/price_calculator.dart' show branchLat, branchLng;
import '../booking_gate_provider.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart' show DoorCode;
import '../widgets/res_location_row.dart';
import 'res_detail_bits_v2.dart';

/// Navigation target of the pickup ([pickup]) or return row — the SAME
/// address / GPS / fallback arguments `ResWhenWhereV2` passes to
/// `ResLocationRow` (GPS first, main-branch coordinates when the branch has
/// none). Used by the CO TEĎ CTA and the action tiles, so every "Navigovat"
/// opens the same place.
({double? lat, double? lng, String? fallback}) resNavTarget(Reservation res, String? branchFullAddress,
    {required bool pickup}) {
  final delivery = (pickup ? res.pickupMethod : res.returnMethod) == 'delivery';
  if (delivery) {
    return pickup
        ? (lat: res.pickupLat, lng: res.pickupLng, fallback: res.pickupAddress)
        : (lat: res.returnLat, lng: res.returnLng, fallback: res.returnAddress);
  }
  return (lat: res.branchLat ?? branchLat, lng: res.branchLng ?? branchLng, fallback: branchFullAddress);
}

/// Opens [resNavTarget] through `ResLocationRow.openNavigation`.
Future<void> resNavigate(Reservation res, String? branchFullAddress, {required bool pickup}) {
  final n = resNavTarget(res, branchFullAddress, pickup: pickup);
  return ResLocationRow.openNavigation(lat: n.lat, lng: n.lng, fallbackAddress: n.fallback);
}

/// "ne 18. 10. do 23:59": the booking's return time; a self-service branch
/// without one returns until 23:59 (its rule), otherwise the date alone.
String resReturnWhen(AppTranslations tr, Reservation res) {
  final date = tripShortDate(tr, res.endDate);
  final rt = (res.returnTime ?? '').trim();
  final hm = rt.length >= 5 ? rt.substring(0, 5) : (res.isSelfService && res.returnMethod != 'delivery' ? '23:59' : null);
  return hm == null ? date : tr.trArgs('v2UxRpReturnBy', {'date': date, 'time': hm});
}

/// Return rules of a live booking (upcoming / active, return at the
/// branch): today's Home checklist line + the kiosk auto-completion note
/// on a self-service branch. Empty otherwise.
List<String> resReturnRules(AppTranslations tr, Reservation res) {
  final st = res.displayStatus;
  if (st != ResStatus.nadchazejici && st != ResStatus.aktivni) return const [];
  if (res.returnMethod == 'delivery' || res.isGearOnly) return const [];
  if (res.isSelfService) return [tr.tr('v2HomeChkReturnSelf'), tr.tr('v2UxRpKioskReturn')];
  if (res.branchType == 'obslužná') return [tr.tr('v2HomeChkReturnStaff')];
  return const [];
}

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
        ResSectionEyebrowV2(tr.tr('v2ResWhenWhere')),
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
          when: resReturnWhen(tr, res),
          isDelivery: res.returnMethod == 'delivery',
          address: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
          lat: res.returnMethod == 'delivery' ? res.returnLat : (res.branchLat ?? branchLat),
          lng: res.returnMethod == 'delivery' ? res.returnLng : (res.branchLng ?? branchLng),
          fallbackAddress: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
        ),
        for (final line in resReturnRules(tr, res))
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 6),
            child: Text(line, style: MgType.small.copyWith(color: MgColors.lead)),
          ),
      ]),
    );
  }
}

/// "Výbava" (white card): sizes chosen at booking (rider + passenger) and
/// "own gear" — straight from the reservation fields. Hidden when the
/// booking has none.
class ResGearV2 extends ConsumerWidget {
  final Reservation res;

  /// Door codes the detail already loaded: with a locker code out (in the
  /// rental term, like the codes card) the header shows "Šatna · dveře č. N"
  /// from the SAME gate info the codes card reads — never a new request.
  final List<DoorCode>? doorCodes;
  const ResGearV2({super.key, required this.res, this.doorCodes});

  static bool _has(String? s) => (s ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final codes = doorCodes ?? const <DoorCode>[];
    final lockerOut = res.inRentalTerm && codes.isNotEmpty && codes.any((c) => c.codeType == 'accessories');
    final door = lockerOut ? ref.watch(bookingGateInfoProvider(res.id)).valueOrNull?.lockerDoor : null;
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MgEyebrowDark(tr.tr('v2ResGear')),
              if (door != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: MgColors.well,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MgColors.line),
                  ),
                  child: Text(tr.trArgs('v2UxRpLockerDoor', {'n': door}),
                      style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
                ),
            ],
          ),
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
