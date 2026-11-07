import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_model.dart';
import '../../ride_provider.dart' show myRidesProvider;
import '../../ride_trip.dart';
import '../../ride_trip_api.dart';
import 'ride_merge_v2.dart' show openRideMergeV2;
import 'ride_trip_card_v2.dart' show tripNameV2;
import 'trip_actions_v2.dart';
import 'trip_detail_screen_v2.dart' show openTripDetailV2;

/// Trip of a ride in its detail (SPEC §9.1 "Cesta" row, v2): a member →
/// "Součást cesty {name} ›" (trip detail) + "Vyjmout z cesty" (with Zpět);
/// not a member and the server knows trips → "Přidat do cesty…" (merge
/// with this ride preselected). Reads the ride list itself, so the old
/// screen's seam needs no new callbacks.
class RideTripRowV2 extends ConsumerWidget {
  final UserRide ride;
  const RideTripRowV2({super.key, required this.ride});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(myRidesProvider).valueOrNull;
    if (rides == null) return const SizedBox.shrink();
    final tr = t(context);
    final items = groupRides(rides);
    RideTrip? trip;
    for (final i in items) {
      if (i is RideListItemTrip && i.trip.rides.any((r) => r.id == ride.id)) trip = i.trip;
    }
    final me = rides.firstWhere((r) => r.id == ride.id, orElse: () => ride);

    Future<void> remove() async {
      final op = await tripApplyV2(ref, rideTripRemovePlan(me));
      if (!context.mounted) return;
      if (op.ok) {
        showTripDoneV2(context, tr.tr('v2RpTripRemoved'), undo: op.undo);
      } else {
        showTripErrorV2(context, op.result);
      }
    }

    if (trip != null) {
      final t0 = trip;
      final name = tripNameV2(tr, t0);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: '${tr.tr('v2RpTripPartOf')} $name',
          excludeSemantics: true,
          child: MgPress(
            scale: 0.98,
            onTap: () => openTripDetailV2(context, t0),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: MgColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MgColors.ink, width: 1.5),
                boxShadow: MgShadows.card,
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(12)),
                  child: const Center(child: MgIcon(MgIcons.route, size: 20, color: MgColors.neon)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr.tr('v2RpTripPartOf'), style: MgType.meta.copyWith(color: MgColors.meta)),
                    MgWordFit(
                      minScale: 0.8,
                      child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                    ),
                  ]),
                ),
                const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
              ]),
            ),
          ),
        ),
        if (me.serverV2)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MgBtnText(label: tr.tr('v2RpTripRemove'), icon: MgIcons.cut, onTap: remove),
          ),
      ]);
    }
    if (!me.serverV2 || !rideTripsAvailable(rides, items)) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: MgBtnText(
        label: tr.tr('v2RpTripAddTo'),
        icon: MgIcons.plus,
        onTap: () => openRideMergeV2(context, preselectRideId: ride.id),
      ),
    );
  }
}
