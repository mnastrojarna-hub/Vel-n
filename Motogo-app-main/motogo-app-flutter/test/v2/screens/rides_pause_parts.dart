// Parts of the v2 ride pause / trips fit matrix (rides_pause_test.dart):
// every recorder phase on every surface (dock bar + selection dock, Domů
// row, Moje row, nav chip, pause sheet, recorder card + buttons), the
// ride / trip cards, merge row, stages and stats cards — each part one
// tall column so the 8 languages × 3 widths × 2 text scales stay quick.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/home/v2/home_record_row_v2.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/v2/record_dock_v2.dart';
import 'package:motogo_app/features/routes/v2/route_nav_skin_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_lists_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_tabs_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_card_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_pause_sheet_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_stages_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_stats_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_trip_card_v2.dart';

import '../support/fakes_rides.dart' show kRideLive;
import '../support/fakes_rides_pause.dart';

/// [child] with its own recorder in [s] (nested scope).
Widget scopedRec(RideRecorderState s, Widget child) =>
    ProviderScope(overrides: [rideRecorderProvider.overrideWith((ref) => FakePauseRecorder(ref, s))], child: child);

Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

/// The Trasy / Moje dock in every phase, plus the Místa selection dock
/// with a running recording (context line + ❚❚ + ■).
Widget docksPart() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in recStates().values) _gap(scopedRec(s, TrasyRecordDockV2(onOpenRecorder: () {}))),
      for (final s in [kRecRiding, kRecAutoPaused, kRecRentalWalk])
        _gap(scopedRec(s, TrasyRecordDockV2(selection: TrasySelection(count: 3, onContinue: () {}, onClear: () {}), onOpenRecorder: () {}))),
    ]);

/// "Zaznamenat jízdu" row of Domů in every phase.
Widget homeRowsPart() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in recStates().values) scopedRec(s, const HomeRecordRowV2()),
      const SizedBox(height: 16),
    ]);

/// Moje "Záznam jízdy" row + the merge row.
Widget mojeRowsPart() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in recStates().values)
          _gap(MojeRecordRowV2(rec: s, hintOpen: false, onHint: () {}, onEnabled: (_) {}, onOpen: () {})),
        MojeMergeRowV2(onTap: () {}),
      ]),
    );

/// The nav chip of every phase (on a map-dark strip) + the pause sheet
/// body of every phase (light, like the sheet).
Widget navAndSheetPart() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: MgColors.panel,
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final s in recStates().values) scopedRec(s, const NavRecChipV2()),
        ]),
      ),
      for (final s in recStates().values)
        Container(
          color: MgColors.surface,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(16),
          child: scopedRec(s, const RidePauseSheetBodyV2()),
        ),
    ]);

/// Recorder card of every phase + the dock buttons + the explainer.
Widget recorderPartsPart() => Container(
      color: MgColors.night,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in recStates().values) _gap(RecorderLiveCardV2(rec: s)),
        _gap(RecorderPauseButtonV2(paused: false, onTap: () {})),
        _gap(RecorderPauseButtonV2(paused: true, onTap: () {})),
        _gap(RecorderStopButtonV2(onTap: () {})),
        _gap(RecorderHowV2(open: true, onTap: () {}, text: 'x')),
      ]),
    );

/// Cards: a multi-day ride (days chip), a recording ride, an explicit trip,
/// a rental group; stages; stats of a ride with pauses / gap / moved pause
/// and of a trip.
Widget cardsPart() => Builder(builder: (context) {
      final rides = kTripRides();
      final alps = tripOf(rides, 't1');
      final rental = tripOf(rides, 'b91');
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RideCardV2(ride: kRideMultiDay, onTap: () {}),
          scopedRec(kRecAutoPaused, RideCardV2(ride: kRideLive, onTap: () {})),
          RideTripCardV2(trip: alps, onTap: () {}),
          scopedRec(kRecRentalWalk, RideTripCardV2(trip: rental, onTap: () {})),
          RideCardV2(ride: kLegacy, onTap: () {}),
          const SizedBox(height: 12),
          RideStagesV2(stages: kRideMultiDay.stages),
          const SizedBox(height: 12),
          RideStatsCardV2(ride: kRideMultiDay),
          const SizedBox(height: 12),
          RideStatsCardV2(ride: alps.aggregate, days: alps.days, rides: alps.rides.length),
          const SizedBox(height: 12),
          RideStatsCardV2(ride: kLegacy),
        ]),
      );
    });
