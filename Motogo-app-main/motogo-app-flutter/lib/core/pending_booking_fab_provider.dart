import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_client.dart';

/// True while the PaymentScreen is on screen. Driven by PaymentScreen's
/// widget lifecycle (initState/dispose), NOT by go_router's matchedLocation.
///
/// Důvod: na platbu se naviguje přes `context.push('/payment')` (imperativně).
/// U imperativního pushe go_router NEAKTUALIZUJE `GoRouterState.of(context)
/// .matchedLocation` ve `ShellRoute` builderu (zůstane na `/booking`), takže
/// kontrola podle route stringu („onPaymentScreen") nikdy nesedí a FAB se
/// neschoval. Tento příznak je navázaný přímo na existenci PaymentScreen, takže
/// funguje bez ohledu na routovací kvírky. AppShell ho čte a skryje všechny
/// plovoucí FAB panely, aby nepřekrývaly tlačítko „Zaplatit".
final paymentScreenActiveProvider = StateProvider<bool>((ref) => false);

/// Pending booking data for the FAB — mirrors _checkAndShowBookingFab()
/// from reservations-ui.js. Shows unpaid bookings within 10-min window.
class PendingBooking {
  final String id;
  final double totalPrice;
  final DateTime createdAt;

  const PendingBooking({
    required this.id,
    required this.totalPrice,
    required this.createdAt,
  });

  /// Remaining milliseconds before expiry (30 min from created_at) —
  /// zrcadlí serverové okno auto_cancel_expired_pending (mig. 20260904b).
  int get remainingMs {
    const expiryMs = 1800000; // 30 minutes
    return expiryMs - DateTime.now().difference(createdAt).inMilliseconds;
  }

  bool get isExpired => remainingMs <= 0;

  /// Format remaining time as "M:SS".
  String get timeLabel {
    final ms = remainingMs;
    if (ms <= 0) return '0:00';
    final min = ms ~/ 60000;
    final sec = (ms % 60000) ~/ 1000;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

/// Streams the current pending booking (if any) with a 1-second tick
/// for the countdown timer. Mirrors _checkAndShowBookingFab +
/// _startBookingFabCountdown from reservations-ui.js.
///
/// Keeps polling every 5 seconds when no booking is found, so newly
/// created bookings are detected (like Capacitor's re-check on every
/// screen navigation via _updateBookingFabVisibility).
final pendingBookingFabProvider =
    StreamProvider.autoDispose<PendingBooking?>((ref) async* {
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    yield null;
    return;
  }

  while (true) {
    // Fetch pending unpaid booking
    Map<String, dynamic>? res;
    try {
      res = await MotoGoSupabase.client
          .from('bookings')
          .select('id, status, payment_status, total_price, created_at')
          .eq('user_id', user.id)
          .inFilter('status', ['reserved', 'pending'])
          .eq('payment_status', 'unpaid')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (_) {
      // Network error — retry after delay
      yield null;
      await Future.delayed(const Duration(seconds: 5));
      continue;
    }

    if (res == null) {
      yield null;
      // No pending booking — re-check in 5 s
      await Future.delayed(const Duration(seconds: 5));
      continue;
    }

    final booking = PendingBooking(
      id: res['id'] as String,
      totalPrice: (res['total_price'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(res['created_at'] as String),
    );

    if (booking.isExpired) {
      yield null;
      await Future.delayed(const Duration(seconds: 5));
      continue;
    }

    // Tick every second for countdown until expired
    while (!booking.isExpired) {
      yield booking;
      await Future.delayed(const Duration(seconds: 1));
    }
    // Expired — loop back to re-check
    yield null;
  }
});

/// Cancel a pending booking — mirrors dismissBookingFab() from
/// reservations-ui.js: sets status=cancelled in DB.
Future<void> cancelPendingBooking(String bookingId) async {
  await MotoGoSupabase.client.from('bookings').update({
    'status': 'cancelled',
    'cancelled_by_source': 'customer',
    'cancellation_reason': 'Zákazník si to rozmyslel',
    'cancelled_at': DateTime.now().toIso8601String(),
  }).eq('id', bookingId).eq('payment_status', 'unpaid');
}
