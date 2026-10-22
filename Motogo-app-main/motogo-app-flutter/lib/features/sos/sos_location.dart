import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/friendly_error.dart';
import '../../core/native/gps_service.dart';
import '../../core/supabase_client.dart';
import 'sos_provider.dart';

/// Výsledek sdílení polohy v SOS. Úspěch se hlásí JEN při [ok] — dřív appka
/// tvrdila „Poloha sdílena" i bez oprávnění, bez GPS nebo bez internetu.
enum SosLocResult { ok, noPermission, serviceOff, noFix, offline, failed }

SosLocResult _fromGps(GpsStatus s) => switch (s) {
      GpsStatus.serviceOff => SosLocResult.serviceOff,
      GpsStatus.denied || GpsStatus.deniedForever => SosLocResult.noPermission,
      _ => SosLocResult.noFix,
    };

/// Poloha pro SOS hlášení s limitem (hlášení nesmí čekat na GPS déle než
/// [limit]). Nic neotevírá — důvod chybějící polohy vrací ve [status].
Future<({Position? pos, GpsStatus status})> sosLocate(
    {Duration limit = const Duration(seconds: 20)}) {
  return GpsService.locate().timeout(limit,
      onTimeout: () => (pos: null, status: GpsStatus.noFix));
}

/// Pošle polohu k incidentu (RPC `sos_share_location` → true jen když
/// incident patří zákazníkovi a uložil se).
Future<SosLocResult> shareLocation(String incidentId, {Position? pos}) async {
  var p = pos;
  if (p == null) {
    final r = await sosLocate();
    if (r.pos == null) return _fromGps(r.status);
    p = r.pos;
  }
  try {
    final ok = await MotoGoSupabase.client.rpc('sos_share_location', params: {
      'p_incident_id': incidentId,
      'p_lat': p!.latitude,
      'p_lng': p.longitude,
    });
    return ok == true ? SosLocResult.ok : SosLocResult.failed;
  } catch (e) {
    FriendlyError.log('sos_share_location', e);
    return FriendlyError.of(e).isNetwork ? SosLocResult.offline : SosLocResult.failed;
  }
}

/// „Sdílet polohu" odkudkoli: k aktivnímu incidentu, jinak založí incident
/// `location_share` rovnou se souřadnicemi.
Future<SosLocResult> shareLocationNow(String? activeIncidentId) async {
  final r = await sosLocate();
  final pos = r.pos;
  if (pos == null) return _fromGps(r.status);
  if (activeIncidentId != null) return shareLocation(activeIncidentId, pos: pos);
  try {
    final id = await createSosIncident(
      type: SosType.locationShare,
      description: 'Sdílení polohy',
      lat: pos.latitude,
      lng: pos.longitude,
    );
    final res = await shareLocation(id, pos: pos);
    // Nový incident už souřadnice nese z INSERTu; existující vážný incident
    // (vrácený místo nového) je dostal přes RPC.
    return res == SosLocResult.offline ? res : SosLocResult.ok;
  } catch (e) {
    FriendlyError.log('sos_location_share_create', e);
    return FriendlyError.of(e).isNetwork ? SosLocResult.offline : SosLocResult.failed;
  }
}
