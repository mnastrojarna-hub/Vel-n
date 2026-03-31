import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import 'reservation_models.dart';

/// Booking select query — matches _getBookingById from reservations-ui.js.
const _bookingSelect =
    '*, motorcycles(*, branches(name, address, city))';

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
  await for (final _ in MotoGoSupabase.client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)) {
    yield await _fetchBookings(user.id);
  }
});

Future<List<Reservation>> _fetchBookings(String userId) async {
  final res = await MotoGoSupabase.client
      .from('bookings')
      .select(_bookingSelect)
      .eq('user_id', userId)
      .order('start_date', ascending: false);

  return (res as List)
      .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
      .toList();
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

/// Door codes for a booking (branch_door_codes).
final doorCodesProvider =
    FutureProvider.family<List<DoorCode>, String>((ref, bookingId) async {
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
});

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
Future<void> rateBooking(String bookingId, int rating) async {
  await MotoGoSupabase.client.from('bookings').update({
    'rating': rating,
    'rated_at': DateTime.now().toIso8601String(),
  }).eq('id', bookingId);
}
