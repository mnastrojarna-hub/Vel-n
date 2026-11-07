// Page states of the v2 ride pause / trips matrix: the recorder in every
// phase, Moje with trips (merge row, trip cards), ride detail of a
// multi-day ride (stages, pauses, "Přidat do cesty…") and of a trip
// member ("Součást cesty"), trip detail (explicit, rental, failed op,
// gone), the merge screen (preselected / too few rides).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/features/routes/ride_trip_api.dart' show RideTripOpResult;
import 'package:motogo_app/features/routes/v2/rides/recorder_screen_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_merge_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/trip_detail_screen_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/trip_detail_view_v2.dart';

import '../support/fakes_rides_pause.dart';
import 'rides_cases.dart' show mojeView, rideDetail;

typedef PauseCase = (Widget Function(), List<Override> Function());

Map<String, PauseCase> pauseRecorderCases() => {
      for (final e in recStates().entries)
        e.key: (() => const RecorderScreenV2(), () => tripOverrides(recorder: e.value)),
    };

Map<String, PauseCase> pausePageCases() => {
      'moje-trips': (
        () => mojeView(rides: AsyncValue.data(kTripRides()), rec: kRecAutoPaused),
        () => tripOverrides(recorder: kRecAutoPaused)
      ),
      'detail-multiday': (() => rideDetail(kRideMultiDay), () => tripOverrides()),
      'detail-member': (() => rideDetail(kTrip2), () => tripOverrides()),
      'trip-explicit': (() => const TripDetailScreenV2(leaderId: 't1'), () => tripOverrides()),
      'trip-rental': (() => const TripDetailScreenV2(leaderId: 'b91'), () => tripOverrides(recorder: kRecRentalWalk)),
      'trip-error': (
        () {
          final t = tripOf(kTripRides(), 't1');
          return TripDetailViewV2(
            trip: t,
            name: t.name!,
            busy: false,
            error: RideTripOpResult.unavailable,
            onBack: () {},
            onRename: () {},
            onShare: () {},
            onDelete: () {},
            onSplit: () {},
            onVisibility: (_) {},
          );
        },
        () => tripOverrides()
      ),
      'trip-gone': (() => const TripDetailScreenV2(leaderId: 'zz'), () => tripOverrides()),
      'merge': (() => const RideMergeScreenV2(preselectRideId: 's1'), () => tripOverrides()),
      'merge-empty': (() => const RideMergeScreenV2(), () => tripOverrides(rides: [kSolo])),
    };
