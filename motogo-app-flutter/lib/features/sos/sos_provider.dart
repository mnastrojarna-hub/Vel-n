import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/supabase_client.dart';

/// SOS incident types — matches CHECK constraint on sos_incidents.type.
class SosType {
  static const theft = 'theft';
  static const accidentMinor = 'accident_minor';
  static const accidentMajor = 'accident_major';
  static const breakdownMinor = 'breakdown_minor';
  static const breakdownMajor = 'breakdown_major';
  static const defectQuestion = 'defect_question';
  static const locationShare = 'location_share';
  static const other = 'other';
}

/// SOS incident from Supabase.
class SosIncident {
  final String id;
  final String type;
  final String status; // reported, acknowledged, in_progress, resolved, closed
  final String? title;
  final String? description;
  final bool? motoRideable;
  final bool? customerFault;
  final String? replacementStatus;
  final String? assignedTo;
  final String? contactPhone;
  final List<String> photos;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  SosIncident({
    required this.id, required this.type, required this.status,
    this.title, this.description, this.motoRideable, this.customerFault,
    this.replacementStatus, this.assignedTo, this.contactPhone,
    this.photos = const [], required this.createdAt, this.resolvedAt,
  });

  factory SosIncident.fromJson(Map<String, dynamic> json) => SosIncident(
    id: json['id'] as String,
    type: json['type'] as String? ?? 'other',
    status: json['status'] as String? ?? 'reported',
    title: json['title'] as String?,
    description: json['description'] as String?,
    motoRideable: json['moto_rideable'] as bool?,
    customerFault: json['customer_fault'] as bool?,
    replacementStatus: json['replacement_status'] as String?,
    assignedTo: json['assigned_to'] as String?,
    contactPhone: json['contact_phone'] as String?,
    photos: (json['photos'] as List?)?.map((e) => e.toString()).toList() ?? [],
    createdAt: DateTime.parse(json['created_at'] as String),
    resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at'] as String) : null,
  );

  bool get isActive => !['resolved', 'closed'].contains(status);
  bool get isSerious => !['breakdown_minor', 'defect_question', 'location_share', 'other'].contains(type);
}

/// SOS timeline entry.
class SosTimelineEntry {
  final String id;
  final String action;
  final String? description;
  final DateTime createdAt;

  SosTimelineEntry({required this.id, required this.action, this.description, required this.createdAt});

  factory SosTimelineEntry.fromJson(Map<String, dynamic> json) => SosTimelineEntry(
    id: json['id'] as String,
    action: json['action'] as String? ?? '',
    description: json['description'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// Active SOS incident for current user (realtime).
final activeSosProvider = StreamProvider<SosIncident?>((ref) async* {
  final user = MotoGoSupabase.currentUser;
  if (user == null) { yield null; return; }

  yield await _fetchActiveIncident(user.id);

  await for (final _ in MotoGoSupabase.client
      .from('sos_incidents')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)) {
    yield await _fetchActiveIncident(user.id);
  }
});

Future<SosIncident?> _fetchActiveIncident(String userId) async {
  final res = await MotoGoSupabase.client
      .from('sos_incidents')
      .select()
      .eq('user_id', userId)
      .not('status', 'in', '("resolved","closed")')
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();
  return res != null ? SosIncident.fromJson(res) : null;
}

/// Timeline entries for an incident (realtime).
final sosTimelineProvider = StreamProvider.family<List<SosTimelineEntry>, String>((ref, incidentId) async* {
  yield await _fetchTimeline(incidentId);
  await for (final _ in MotoGoSupabase.client
      .from('sos_timeline')
      .stream(primaryKey: ['id'])
      .eq('incident_id', incidentId)) {
    yield await _fetchTimeline(incidentId);
  }
});

Future<List<SosTimelineEntry>> _fetchTimeline(String incidentId) async {
  final res = await MotoGoSupabase.client
      .from('sos_timeline')
      .select()
      .eq('incident_id', incidentId)
      .order('created_at');
  return (res as List).map((e) => SosTimelineEntry.fromJson(e)).toList();
}

/// Create SOS incident — mirrors _sosEnsureIncident + apiCreateSosIncident.
Future<String?> createSosIncident({
  required String type,
  required String description,
  String? bookingId,
  String? motoId,
  double? lat,
  double? lng,
}) async {
  try {
    // Check for existing active serious incident
    final user = MotoGoSupabase.currentUser;
    if (user == null) return null;

    final existing = await MotoGoSupabase.client
        .from('sos_incidents')
        .select('id')
        .eq('user_id', user.id)
        .not('status', 'in', '("resolved","closed")')
        .not('type', 'in', '("breakdown_minor","defect_question","location_share","other")')
        .limit(1)
        .maybeSingle();

    if (existing != null) return existing['id'] as String;

    // Find active booking if not provided
    bookingId ??= await _findActiveBookingId(user.id);
    if (bookingId != null && motoId == null) {
      motoId = await _findMotoId(bookingId);
    }

    final res = await MotoGoSupabase.client.from('sos_incidents').insert({
      'user_id': user.id,
      'booking_id': bookingId,
      'moto_id': motoId,
      'type': type,
      'title': description,
      'description': description,
      'latitude': lat,
      'longitude': lng,
    }).select('id').single();

    return res['id'] as String;
  } catch (e) {
    return null;
  }
}

Future<String?> _findActiveBookingId(String userId) async {
  final res = await MotoGoSupabase.client.from('bookings')
      .select('id').eq('user_id', userId)
      .inFilter('status', ['active', 'reserved'])
      .eq('payment_status', 'paid')
      .order('created_at', ascending: false).limit(1).maybeSingle();
  return res?['id'] as String?;
}

Future<String?> _findMotoId(String bookingId) async {
  final res = await MotoGoSupabase.client.from('bookings')
      .select('moto_id').eq('id', bookingId).maybeSingle();
  return res?['moto_id'] as String?;
}

/// Share GPS location — mirrors sos_share_location RPC.
Future<void> shareLocation(String incidentId) async {
  try {
    final pos = await _getGps();
    if (pos == null) return;
    await MotoGoSupabase.client.from('sos_incidents').update({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
    }).eq('id', incidentId);
    await MotoGoSupabase.client.from('sos_timeline').insert({
      'incident_id': incidentId,
      'action': 'Zákazník sdílel polohu: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
    });
  } catch (_) {}
}

/// Get GPS position with fallback — mirrors _sosGetGPS.
Future<Position?> _getGps() async {
  try {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 30),
      ),
    );
  } catch (_) {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 30),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Upload SOS photos — mirrors uploadSOSPhotos from sos-photo.js.
Future<List<String>> uploadSosPhotos(String incidentId, List<XFile> photos) async {
  final urls = <String>[];
  for (var i = 0; i < photos.length; i++) {
    final bytes = await photos[i].readAsBytes();
    final path = '$incidentId/${DateTime.now().millisecondsSinceEpoch}-$i.jpg';
    await MotoGoSupabase.client.storage.from('sos-photos').uploadBinary(path, bytes);
    final url = MotoGoSupabase.client.storage.from('sos-photos').getPublicUrl(path);
    urls.add(url);
  }
  if (urls.isNotEmpty) {
    await MotoGoSupabase.client.from('sos_incidents').update({'photos': urls}).eq('id', incidentId);
  }
  return urls;
}
