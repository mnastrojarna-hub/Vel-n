import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import 'reservation_models.dart';

/// Booking select query — matches _getBookingById from reservations-ui.js.
const _bookingSelect =
    '*, motorcycles(*, branches(name, address, city, gps_lat, gps_lng))';

/// Fetches all user bookings with realtime subscription.
/// Mirrors apiFetchMyBookings() + realtime channel.
final reservationsProvider =
    StreamProvider<List<Reservation>>((ref) async* {
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    yield [];
    return;
  }

  // Initial fetch
  final initial = await _fetchBookings(user.id);
  yield initial;

  // Realtime subscription — bookings table changes for this user
  try {
    await for (final _ in MotoGoSupabase.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)) {
      yield await _fetchBookings(user.id);
    }
  } catch (e) {
    if (await handleAuthError(e)) return;
    rethrow;
  }
});

Future<List<Reservation>> _fetchBookings(String userId) async {
  try {
    final res = await MotoGoSupabase.client
        .from('bookings')
        .select(_bookingSelect)
        .eq('user_id', userId)
        .order('start_date', ascending: false);

    return (res as List)
        .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    if (await handleAuthError(e)) return [];
    rethrow;
  }
}

/// Single reservation by ID.
final reservationByIdProvider =
    FutureProvider.family<Reservation?, String>((ref, id) async {
  final res = await MotoGoSupabase.client
      .from('bookings')
      .select(_bookingSelect)
      .eq('id', id)
      .maybeSingle();

  if (res == null) return null;
  return Reservation.fromJson(res);
});

/// Door codes for a booking (branch_door_codes) — realtime stream.
/// Reacts to code generation, release (withheld → sent), and deactivation.
final doorCodesProvider =
    StreamProvider.family<List<DoorCode>, String>((ref, bookingId) async* {
  // Initial fetch
  yield await _fetchDoorCodes(bookingId);

  // Realtime subscription
  try {
    await for (final _ in MotoGoSupabase.client
        .from('branch_door_codes')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)) {
      yield await _fetchDoorCodes(bookingId);
    }
  } catch (e) {
    if (await handleAuthError(e)) return;
    rethrow;
  }
});

Future<List<DoorCode>> _fetchDoorCodes(String bookingId) async {
  try {
    final res = await MotoGoSupabase.client
        .from('branch_door_codes')
        .select()
        .eq('booking_id', bookingId)
        .eq('is_active', true);

    return (res as List)
        .map((e) => DoorCode.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

/// Try to release withheld door codes by calling RPC.
/// Returns null on success or error message on failure.
Future<String?> releaseDoorCodes(String bookingId) async {
  try {
    final res = await MotoGoSupabase.client.rpc(
      'release_my_door_codes',
      params: {'p_booking_id': bookingId},
    );
    final result = res as Map<String, dynamic>?;
    if (result != null && result['success'] == true) return null;
    return result?['error'] as String? ?? 'Unknown error';
  } catch (e) {
    return e.toString();
  }
}

class DoorCode {
  final String id;
  final String codeType; // motorcycle, accessories
  final String doorCode;
  final bool isActive;
  final bool sentToCustomer;
  final String? withheldReason;

  DoorCode({
    required this.id,
    required this.codeType,
    required this.doorCode,
    required this.isActive,
    required this.sentToCustomer,
    this.withheldReason,
  });

  factory DoorCode.fromJson(Map<String, dynamic> json) => DoorCode(
        id: json['id'] as String,
        codeType: json['code_type'] as String? ?? '',
        doorCode: json['door_code'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? false,
        sentToCustomer: json['sent_to_customer'] as bool? ?? false,
        withheldReason: json['withheld_reason'] as String?,
      );
}

/// Current filter for reservation list.
final resFilterProvider = StateProvider<String>((_) => 'all');

/// Filtered reservations.
final filteredReservationsProvider =
    Provider<AsyncValue<List<Reservation>>>((ref) {
  final filter = ref.watch(resFilterProvider);
  return ref.watch(reservationsProvider).whenData((list) {
    if (filter == 'all') return list;
    return list.where((r) {
      return r.displayStatus.name == filter;
    }).toList();
  });
});

/// Cancel booking via RPC — mirrors apiCancelBooking.
Future<String?> cancelBooking(String bookingId, String reason) async {
  try {
    await MotoGoSupabase.client.rpc('cancel_booking_tracked', params: {
      'p_booking_id': bookingId,
      'p_reason': reason,
    });
    return null; // success
  } catch (e) {
    return 'Chyba storna: $e';
  }
}

/// Submit rating for a completed booking.
/// Returns null on success or error message string on failure.
Future<String?> rateBooking(String bookingId, int rating) async {
  try {
    await MotoGoSupabase.client.from('bookings').update({
      'rating': rating,
      'rated_at': DateTime.now().toIso8601String(),
    }).eq('id', bookingId);
    return null;
  } catch (e) {
    if (await handleAuthError(e)) return null;
    return e.toString();
  }
}

/// SOS incidents for a booking — mirrors _loadSosForDetail from reservations-edit.js.
final sosIncidentsProvider =
    FutureProvider.family<List<SosIncident>, String>((ref, bookingId) async {
  try {
    final res = await MotoGoSupabase.client
        .from('sos_incidents')
        .select('id, type, title, status, severity, created_at, resolved_at, description')
        .eq('booking_id', bookingId)
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => SosIncident.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

class SosIncident {
  final String id;
  final String type;
  final String? title;
  final String status;
  final String? severity;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? description;

  const SosIncident({
    required this.id,
    required this.type,
    this.title,
    required this.status,
    this.severity,
    required this.createdAt,
    this.resolvedAt,
    this.description,
  });

  factory SosIncident.fromJson(Map<String, dynamic> json) => SosIncident(
    id: json['id'] as String,
    type: json['type'] as String? ?? 'other',
    title: json['title'] as String?,
    status: json['status'] as String? ?? 'reported',
    severity: json['severity'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    resolvedAt: json['resolved_at'] != null
        ? DateTime.tryParse(json['resolved_at'] as String)
        : null,
    description: json['description'] as String?,
  );

  String get shortId => '#${id.substring(id.length - 8).toUpperCase()}';

  String get typeLabel {
    const labels = {
      'theft': 'Krádež',
      'accident_minor': 'Nehoda (lehká)',
      'accident_major': 'Nehoda (těžká)',
      'breakdown_minor': 'Porucha (lehká)',
      'breakdown_major': 'Porucha (těžká)',
      'defect_question': 'Závada / dotaz',
      'other': 'Jiné',
    };
    return labels[type] ?? type;
  }

  String get statusLabel {
    const labels = {
      'reported': 'Nahlášeno',
      'acknowledged': 'Přijato',
      'in_progress': 'Řeší se',
      'resolved': 'Vyřešeno',
      'closed': 'Uzavřeno',
    };
    return labels[status] ?? status;
  }
}
