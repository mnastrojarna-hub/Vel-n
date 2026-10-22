import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import 'ride_flags.dart';
import 'ride_provider.dart';
import 'ride_server_api.dart';

/// Šev mezi záznamníkem a serverem — v testech se přepíše falešným
/// serverem (`rideServerSeamProvider.overrideWithValue(...)`), v appce volá
/// skutečná RPC.
class RideServerSeam {
  const RideServerSeam();

  bool get signedIn => MotoGoSupabase.currentUser != null;

  /// Nový server: `start_user_trip` (ví o pauzách, nikdy nedělí výpůjčku).
  Future<RideTripStart> startTrip(String? bookingId) => startUserTrip(bookingId);

  /// Starý server / fallback: `start_user_ride` bez polohy (jako dřív).
  Future<RideStart?> startLegacy(String? bookingId) => startUserRide(bookingId: bookingId);

  Future<RideAppendOutcome> append(String id, List<List<double>> points, {double? maxSpeedKmh}) =>
      appendRideTrack(id, points, maxSpeedKmh: maxSpeedKmh);

  Future<RideFinish?> finish(String id, {List<List<double>> points = const []}) =>
      finishUserRide(id, points: points);

  Future<bool?> probe() => probeRideServerV2();

  Future<RideAutoPauseFlag?> fetchFlag() => fetchRideAutoPauseFlag();
}

final rideServerSeamProvider = Provider<RideServerSeam>((ref) => const RideServerSeam());
