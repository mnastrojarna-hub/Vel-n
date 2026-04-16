import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth_guard.dart';
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

/// Customer fault state — mirrors _sosFault from ui-sos-core.js.
/// null = breakdown (always free), false = not-at-fault, true = at-fault.
final sosFaultProvider = StateProvider<bool?>((ref) => null);

/// Customer decision after immobile screen.
enum SosCustomerDecision { replacement, endRide }

/// Whether the motorcycle was secured (for theft).
/// true = secured (free replacement), false = unsecured (paid).
final sosTheftSecuredProvider = StateProvider<bool?>((ref) => null);

/// Done screen context — determines which done variant to show.
enum SosDoneType {
  accidentMinor,      // Lehká nehoda → "Šťastnou cestu"
  theftReported,      // Krádež nahlášena
  towOrdered,         // Odtah objednán (end ride)
  towFree,            // Odtah zdarma (porucha/nezaviněná)
  replacementFree,    // Náhrada zdarma objednána
  replacementPaid,    // Náhrada zaplacena
  breakdownMinor,     // Drobná závada → "Šťastnou cestu"
  serviceSelf,        // Servis na vlastní pěst
  generic,            // Fallback
}

final sosDoneTypeProvider = StateProvider<SosDoneType>((ref) => SosDoneType.generic);

/// Optional model name for done screen (replacement flow).
final sosDoneModelProvider = StateProvider<String?>((ref) => null);

/// Optional total paid for done screen.
final sosDonePaidProvider = StateProvider<double?>((ref) => null);

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
  final String? bookingId;
  final List<String> photos;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final DateTime? bookingEndDate; // from joined booking

  SosIncident({
    required this.id, required this.type, required this.status,
    this.title, this.description, this.motoRideable, this.customerFault,
    this.replacementStatus, this.assignedTo, this.contactPhone,
    this.bookingId,
    this.photos = const [], required this.createdAt, this.resolvedAt,
    this.bookingEndDate,
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
    bookingId: json['booking_id'] as String?,
    photos: (json['photos'] as List?)?.map((e) => e.toString()).toList() ?? [],
    createdAt: DateTime.parse(json['created_at'] as String),
    bookingEndDate: json['bookings']?['end_date'] != null
        ? DateTime.tryParse(json['bookings']['end_date'] as String)
        : null,
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

  try {
    await for (final _ in MotoGoSupabase.client
        .from('sos_incidents')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)) {
      yield await _fetchActiveIncident(user.id);
    }
  } catch (e) {
    if (await handleAuthError(e)) return;
    rethrow;
  }
});

Future<SosIncident?> _fetchActiveIncident(String userId) async {
  try {
    final res = await MotoGoSupabase.client
        .from('sos_incidents')
        .select('*, bookings(end_date)')
        .eq('user_id', userId)
        .not('status', 'in', '("resolved","closed")')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return res != null ? SosIncident.fromJson(res) : null;
  } catch (e) {
    if (await handleAuthError(e)) return null;
    rethrow;
  }
}

/// Timeline entries for an incident (realtime).
final sosTimelineProvider = StreamProvider.family<List<SosTimelineEntry>, String>((ref, incidentId) async* {
  yield await _fetchTimeline(incidentId);
  try {
    await for (final _ in MotoGoSupabase.client
        .from('sos_timeline')
        .stream(primaryKey: ['id'])
        .eq('incident_id', incidentId)) {
      yield await _fetchTimeline(incidentId);
    }
  } catch (e) {
    if (await handleAuthError(e)) return;
    rethrow;
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

/// Create SOS incident via direct INSERT — matches original Capacitor app
/// (api-messaging.js: apiCreateSosIncident).
/// RLS allows customer INSERT on sos_incidents (user_id = uid).
/// Throws on error so callers can display the actual error message.
Future<String> createSosIncident({
  required String type,
  required String description,
  String? bookingId,
  String? motoId,
  bool? isFault,
  double? lat,
  double? lng,
}) async {
  // Check for existing active serious incident
  final user = MotoGoSupabase.currentUser;
  if (user == null) throw Exception('Nepřihlášen — přihlaste se znovu');

  final existing = await MotoGoSupabase.client
      .from('sos_incidents')
      .select('id')
      .eq('user_id', user.id)
      .not('status', 'in', '("resolved","closed")')
      .inFilter('type', ['theft', 'accident_minor', 'accident_major', 'breakdown_major'])
      .limit(1)
      .maybeSingle();

  if (existing != null) return existing['id'] as String;

  // Find active booking if not provided
  bookingId ??= await _findActiveBookingId(user.id);
  if (bookingId != null && motoId == null) {
    motoId = await _findMotoId(bookingId);
  }

  // Direct INSERT — original app uses this instead of RPC
  final data = <String, dynamic>{
    'user_id': user.id,
    'type': type,
    'status': 'reported',
    'description': description,
  };
  if (bookingId != null) data['booking_id'] = bookingId;
  if (motoId != null) data['moto_id'] = motoId;
  if (lat != null) data['latitude'] = lat;
  if (lng != null) data['longitude'] = lng;
  if (isFault != null) data['customer_fault'] = isFault;

  final res = await MotoGoSupabase.client
      .from('sos_incidents')
      .insert(data)
      .select()
      .single();

  return res['id'] as String;
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

/// Share GPS location via sos_share_location RPC.
/// DB: sos_share_location(p_incident_id, p_lat, p_lng) → boolean
Future<void> shareLocation(String incidentId) async {
  try {
    final pos = await _getGps();
    if (pos == null) return;
    await MotoGoSupabase.client.rpc('sos_share_location', params: {
      'p_incident_id': incidentId,
      'p_lat': pos.latitude,
      'p_lng': pos.longitude,
    });
  } catch (_) {}
}

/// Get GPS position with fallback — mirrors _sosGetGPS.
/// Permission is already granted at onboarding — just check, don't re-ask.
Future<Position?> _getGps() async {
  try {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 30),
    );
  } catch (_) {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 30),
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

/// End ride + request tow — mirrors sosEndRide() from ui-sos-core.js.
/// Sets customer_decision='end_ride', requests tow, ends booking.
Future<bool> sosEndRide(String incidentId, {required bool isFault}) async {
  try {
    await MotoGoSupabase.client.from('sos_incidents').update({
      'customer_decision': 'end_ride',
      'moto_rideable': false,
    }).eq('id', incidentId);

    // Request tow via timeline entry (admin picks it up)
    final faultLabel = isFault ? 'zaviněná' : 'nezaviněná / porucha';
    await MotoGoSupabase.client.from('sos_timeline').insert({
      'incident_id': incidentId,
      'action': 'Zákazník ukončuje jízdu — žádá odtah ($faultLabel)',
    });
    return true;
  } catch (_) {
    return false;
  }
}

/// Check if booking had delivery (customer picked up at location).
/// Returns true if delivery was used → tow is free.
/// Returns false if customer was returning to branch → tow is paid.
Future<bool> checkBookingHadDelivery(String? bookingId) async {
  if (bookingId == null) return false;
  try {
    final res = await MotoGoSupabase.client.from('bookings')
        .select('delivery_fee')
        .eq('id', bookingId)
        .maybeSingle();
    if (res == null) return false;
    final fee = res['delivery_fee'];
    return fee != null && (fee as num) > 0;
  } catch (_) {
    return false;
  }
}

/// Upload service invoice photo — attached to breakdown incident.
Future<String?> uploadServiceInvoice(String incidentId, XFile photo) async {
  try {
    final bytes = await photo.readAsBytes();
    final path = '$incidentId/invoice-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await MotoGoSupabase.client.storage.from('sos-photos').uploadBinary(path, bytes);
    final url = MotoGoSupabase.client.storage.from('sos-photos').getPublicUrl(path);

    await MotoGoSupabase.client.from('sos_timeline').insert({
      'incident_id': incidentId,
      'action': 'Zákazník nahrál fakturu za servis',
      'description': url,
    });
    return url;
  } catch (_) {
    return null;
  }
}
