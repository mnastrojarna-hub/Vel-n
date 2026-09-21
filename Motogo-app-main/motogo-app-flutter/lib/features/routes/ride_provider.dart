import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import 'ride_model.dart';

/// Datová vrstva „Mých jízd" — všechno jde přes SECURITY DEFINER RPC
/// (server si sám ověří vlastníka jízdy i rezervaci, klient nic nepodvrhne).

/// Moje jízdy (nejnovější první). Nepřihlášený → prázdný seznam.
final myRidesProvider = FutureProvider<List<UserRide>>((ref) async {
  if (MotoGoSupabase.currentUser == null) return const [];
  try {
    final res = await MotoGoSupabase.client.rpc('get_my_rides');
    return _parseRides(res);
  } catch (e) {
    debugPrint('[rides] get_my_rides selhalo: $e');
    return const [];
  }
});

/// Jízdy k jedné rezervaci — zobrazuje se v detailu výpůjčky (historie).
final bookingRidesProvider =
    FutureProvider.family<List<UserRide>, String>((ref, bookingId) async {
  if (MotoGoSupabase.currentUser == null) return const [];
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_booking_rides', params: {'p_booking_id': bookingId});
    return _parseRides(res);
  } catch (e) {
    debugPrint('[rides] get_booking_rides selhalo: $e');
    return const [];
  }
});

List<UserRide> _parseRides(dynamic res) {
  final list = res is List ? res : const [];
  final out = <UserRide>[];
  for (final e in list) {
    if (e is Map) {
      final r = UserRide.fromJson(Map<String, dynamic>.from(e));
      if (r != null) out.add(r);
    }
  }
  return out;
}

/// Zahájí (nebo obnoví po restartu appky) záznam jízdy. Rezervaci a motorku
/// si dohledá server podle běžící výpůjčky. Vrací id jízdy, jinak null.
Future<String?> startUserRide({String? bookingId, double? lat, double? lng}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('start_user_ride', params: {
      'p_booking_id': bookingId,
      'p_lat': lat,
      'p_lng': lng,
    });
    if (res is Map && res['success'] == true) return res['id']?.toString();
  } catch (e) {
    debugPrint('[rides] start_user_ride selhalo: $e');
  }
  return null;
}

/// Výsledek odeslání dávky bodů.
///   [ok]       – uloženo, dávku můžeme zahodit
///   [retry]    – výpadek sítě / serveru, body si necháme na příště
///   [finished] – server jízdu mezitím uzavřel (noční úklid zatuhlých
///                nahrávek). Do hotové jízdy se už nepřidává, takže má
///                smysl lokální záznam zapomenout a začít nový.
enum RideAppendResult { ok, retry, finished }

/// Pošle dávku GPS bodů `[[lat,lng,ts,kmh,alt],…]` do rozjeté jízdy.
Future<RideAppendResult> appendRideTrack(String rideId, List<List<double>> points,
    {double? maxSpeedKmh}) async {
  if (points.isEmpty) return RideAppendResult.ok;
  try {
    final res = await MotoGoSupabase.client.rpc('append_ride_track', params: {
      'p_ride_id': rideId,
      'p_points': points,
      'p_max_speed_kmh': maxSpeedKmh,
    });
    if (res is Map && res['success'] == true) return RideAppendResult.ok;
    final err = res is Map ? res['error']?.toString() : null;
    if (err == 'ride_finished' || err == 'ride_not_found') {
      debugPrint('[rides] append_ride_track: jízda už není rozjetá ($err)');
      return RideAppendResult.finished;
    }
    return RideAppendResult.retry;
  } catch (e) {
    debugPrint('[rides] append_ride_track selhalo: $e');
    return RideAppendResult.retry;
  }
}

/// Výsledek ukončení jízdy — `discarded` = příliš krátká (< 1 km), zahozena.
class RideFinish {
  final bool discarded;
  final double distanceKm;
  const RideFinish({required this.discarded, required this.distanceKm});
}

Future<RideFinish?> finishUserRide(String rideId,
    {List<List<double>> points = const [], String? name}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('finish_user_ride', params: {
      'p_ride_id': rideId,
      'p_points': points,
      'p_name': name,
    });
    if (res is Map && res['success'] == true) {
      return RideFinish(
        discarded: res['discarded'] == true,
        distanceKm: (res['distance_km'] as num?)?.toDouble() ?? 0,
      );
    }
  } catch (e) {
    debugPrint('[rides] finish_user_ride selhalo: $e');
  }
  return null;
}

/// Ručně poskládaná jízda (start → zastávky → cíl).
Future<String?> createManualRide({
  required String name,
  String? description,
  required List<Map<String, dynamic>> points,
}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('create_manual_ride', params: {
      'p_name': name,
      'p_description': description,
      'p_points': points,
    });
    if (res is Map && res['success'] == true) return res['id']?.toString();
  } catch (e) {
    debugPrint('[rides] create_manual_ride selhalo: $e');
  }
  return null;
}

/// Úprava jízdy — název, popis, sdílení (`private`/`public`), titulní fotka.
Future<bool> updateUserRide(
  String id, {
  String? name,
  String? description,
  String? visibility,
  String? coverImage,
}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('update_user_ride', params: {
      'p_id': id,
      'p_name': name,
      'p_description': description,
      'p_visibility': visibility,
      'p_cover_image': coverImage,
    });
    return res is Map && res['success'] == true;
  } catch (e) {
    debugPrint('[rides] update_user_ride selhalo: $e');
    return false;
  }
}

Future<bool> deleteUserRide(String id) async {
  try {
    final res =
        await MotoGoSupabase.client.rpc('delete_user_ride', params: {'p_id': id});
    return res is Map && res['success'] == true;
  } catch (e) {
    debugPrint('[rides] delete_user_ride selhalo: $e');
    return false;
  }
}

/// Vloží / upraví bod jízdy (zastávka, start, cíl). `id == null` = nový bod.
Future<String?> saveRidePoint({
  required String rideId,
  String? id,
  String kind = 'stop',
  String? name,
  String? note,
  double? lat,
  double? lng,
  List<String>? photos,
  int? sortOrder,
}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('save_ride_point', params: {
      'p_ride_id': rideId,
      'p_id': id,
      'p_kind': kind,
      'p_name': name,
      'p_note': note,
      'p_lat': lat,
      'p_lng': lng,
      'p_photos': photos,
      'p_sort_order': sortOrder,
    });
    if (res is Map && res['success'] == true) return res['id']?.toString();
  } catch (e) {
    debugPrint('[rides] save_ride_point selhalo: $e');
  }
  return null;
}

Future<bool> deleteRidePoint(String id) async {
  try {
    final res =
        await MotoGoSupabase.client.rpc('delete_ride_point', params: {'p_id': id});
    return res is Map && res['success'] == true;
  } catch (e) {
    debugPrint('[rides] delete_ride_point selhalo: $e');
    return false;
  }
}

/// Nahraje fotky zastávky do bucketu `media`, prefix `rides/<uid>/…`
/// (jediný povolený prefix pro fotky jízd). Vadná fotka se tiše přeskočí.
Future<List<String>> uploadRidePhotos(String uid, List<XFile> photos) async {
  final urls = <String>[];
  final ts = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < photos.length; i++) {
    try {
      final x = photos[i];
      final bytes = await x.readAsBytes();
      final ext = x.name.contains('.') ? x.name.split('.').last : 'jpg';
      final path = 'rides/$uid/${ts}_$i.$ext';
      await MotoGoSupabase.client.storage.from('media').uploadBinary(path, bytes);
      urls.add(MotoGoSupabase.client.storage.from('media').getPublicUrl(path));
    } catch (e) {
      debugPrint('[rides] upload fotky selhal: $e');
    }
  }
  return urls;
}
