// Screen states of the Jízdy v2 matrix (PLAN §5.3 "Rides"): Moje (each
// sub-screen, logged out, recording, loading / error / empty), ride detail
// (S MotoGo, soukromá, výpadek signálu, chybějící jízda), recorder (idle,
// manual, rental, weak GPS, auto-record off), stop editor (new / edit +
// error), dialogs and the share sheet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/widgets/map_tile_errors.dart';
import 'package:motogo_app/features/routes/active_ride_provider.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_view_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_screen_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_detail_view_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_point_sheet_v2.dart';

import '../support/fakes_rides.dart';

typedef RideCase = (Widget Function(), List<Override> Function());

/// Cached images need a temp dir (path_provider) in tests.
void ridesMockPathProvider() {
  final dir = Directory.systemTemp.createTempSync('mg_rides_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
}

/// Unmounts and cancels the map-tile retry timer (tiles fail in tests).
Future<void> ridesEnd(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  MapTileErrors.retry();
}

/// Records which callback of a dumb view fired.
class RideTaps {
  final List<String> log = [];
  void Function() cb(String name) => () => log.add(name);
}

MojeViewV2 mojeView({
  bool loggedIn = true,
  int tab = 0,
  AsyncValue<List<UserRide>>? rides,
  AsyncValue<List<SavedRoute>>? routes,
  AsyncValue<List<VisitedPlace>>? places,
  ActiveRide? active,
  List<ActiveRide>? history,
  RideRecorderState rec = kRecIdle,
  RideTaps? taps,
}) {
  final t = taps ?? RideTaps();
  return MojeViewV2(
    loggedIn: loggedIn,
    tab: tab,
    onTab: (i) => t.log.add('tab:$i'),
    rides: rides ?? AsyncValue.data(kRides),
    routes: routes ?? AsyncValue.data(kSavedRoutes),
    places: places ?? AsyncValue.data(kPlaces),
    active: active,
    history: history ?? kHistory,
    rec: rec,
    unread: 2,
    onBack: t.cb('back'),
    onRefresh: () async => t.log.add('refresh'),
    onNavTab: (i) => t.log.add('nav:$i'),
    onCreateRoute: t.cb('create'),
    onLogin: t.cb('login'),
    onAutoRecord: (v) => t.log.add('auto:$v'),
    onOpenSaved: (r) => t.log.add('openSaved:${r.id}'),
    onNavSaved: (r) => t.log.add('navSaved:${r.id}'),
    onDeleteSaved: (r) => t.log.add('delSaved:${r.id}'),
    onRetrySaved: t.cb('retrySaved'),
    onOpenPlace: (p, all) => t.log.add('openPlace:${p.id}'),
    onNavPlace: (p) => t.log.add('navPlace:${p.id}'),
    onRetryPlaces: t.cb('retryPlaces'),
    onOpenHistory: (r, all) => t.log.add('openHist:${r.id}'),
    onHistoryGo: (r, a) => t.log.add('go:${r.id}:$a'),
    onHistoryDelete: (r, a) => t.log.add('delHist:${r.id}:$a'),
  );
}

RideDetailViewV2 rideDetail(UserRide ride, {RideTaps? taps, bool busy = false}) {
  final t = taps ?? RideTaps();
  return RideDetailViewV2(
    ride: ride,
    busy: busy,
    onBack: t.cb('back'),
    onEdit: t.cb('edit'),
    onShare: t.cb('share'),
    onDelete: t.cb('delete'),
    onMapTap: (p) => t.log.add('map'),
    onPointTap: (i) => t.log.add('pointTap:$i'),
    onEditPoint: (p) => t.log.add('editPoint:${p.id}'),
    onVisibility: (v) => t.log.add('visibility:$v'),
  );
}

RidePointSheetV2View pointSheet({bool isNew = false, String? error, RideTaps? taps}) {
  final t = taps ?? RideTaps();
  return RidePointSheetV2View(
    isNew: isNew,
    busy: false,
    error: error,
    name: TextEditingController(text: isNew ? '' : 'Rozhledna Děvičky'),
    note: TextEditingController(text: isNew ? '' : 'Výhled na celé Pálavské vrchy.'),
    photos: isNew ? const [] : const ['https://example.invalid/a.jpg', 'https://example.invalid/b.jpg'],
    newPhotoPaths: const [],
    maxPhotos: 8,
    onDelete: isNew ? null : t.cb('delete'),
    onClose: t.cb('close'),
    onSave: t.cb('save'),
    onPick: t.cb('pick'),
    onRemovePhoto: (i) => t.log.add('remove:$i'),
    onRemoveNew: (i) => t.log.add('removeNew:$i'),
  );
}

Map<String, RideCase> mojeCases() => {
      'rides': (() => mojeView(), () => ridesOverrides()),
      'rides-recording': (() => mojeView(rec: kRecManual), () => ridesOverrides(recorder: kRecManual)),
      'rides-auto-gps': (
        () => mojeView(rec: kRecGpsLost.copyWith(manual: false)),
        () => ridesOverrides(recorder: kRecGpsLost.copyWith(manual: false))
      ),
      'rides-empty': (() => mojeView(rides: const AsyncValue.data([])), () => ridesOverrides()),
      'rides-loading': (() => mojeView(rides: const AsyncValue.loading()), () => ridesOverrides()),
      'places': (() => mojeView(tab: 1), () => ridesOverrides()),
      'places-error': (
        () => mojeView(tab: 1, places: AsyncValue.error(Exception('SocketException: offline'), StackTrace.empty)),
        () => ridesOverrides()
      ),
      'places-empty': (() => mojeView(tab: 1, places: const AsyncValue.data([])), () => ridesOverrides()),
      'history': (() => mojeView(tab: 2, active: kHistoryActive), () => ridesOverrides()),
      'history-empty': (() => mojeView(tab: 2, history: const []), () => ridesOverrides()),
      'logged-out': (
        () => mojeView(loggedIn: false, rides: const AsyncValue.data([]), routes: const AsyncValue.data([]), places: const AsyncValue.data([])),
        () => ridesOverrides(loyalty: null)
      ),
    };

Map<String, RideCase> detailCases() => {
      'motogo': (() => rideDetail(kRideMg), () => ridesOverrides()),
      'private': (() => rideDetail(kRidePrivate), () => ridesOverrides()),
      'gap': (() => rideDetail(kRideGap, busy: true), () => ridesOverrides()),
      'missing': (() => RideMissingV2(onBack: () {}), () => ridesOverrides()),
    };

Map<String, RideCase> recorderCases() => {
      'idle': (() => const RecorderScreenV2(), () => ridesOverrides()),
      'manual': (() => const RecorderScreenV2(), () => ridesOverrides(recorder: kRecManual)),
      'auto': (() => const RecorderScreenV2(), () => ridesOverrides(recorder: kRecAuto)),
      'gps-lost': (() => const RecorderScreenV2(), () => ridesOverrides(recorder: kRecGpsLost)),
      'auto-off': (() => const RecorderScreenV2(), () => ridesOverrides(recorder: kRecOff)),
    };

Map<String, RideCase> pointCases() => {
      'new': (() => pointSheet(isNew: true), () => ridesOverrides()),
      'edit-error': (
        () => pointSheet(error: 'Zastávku se nepodařilo uložit. Text i fotky ti zůstávají.'),
        () => ridesOverrides()
      ),
    };
