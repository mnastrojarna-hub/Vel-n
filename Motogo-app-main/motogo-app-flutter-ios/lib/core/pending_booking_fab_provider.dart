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

/// True dokud je na obrazovce některý z APP-LEVEL overlayů (jazyk, oprávnění,
/// intro). Ty sedí ve `Stack`u v `MaterialApp.builder` AŽ ZA `child!`, takže
/// se kreslí NAD dialogem level-up oslavy — kdyby se oslava spustila pod nimi,
/// 67s video by běželo neviditelně a zapsalo by se jako „už oslaveno".
/// `LoyaltyLevelUpWatcher` proto oslavu odloží (bez zápisu) dokud je true.
final onboardingOverlayActiveProvider = StateProvider<bool>((ref) => false);

/// Pending booking data for the FAB — mirrors _checkAndShowBookingFab()
/// from reservations-ui.js. Shows unpaid bookings within the 30-min window
/// (server: auto_cancel_expired_pending, app = 30 min).
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

/// Jak často se DB ptáme, jestli rezervace (ještě) čeká na platbu — sekundy.
/// Platí jak pro hledání nové rezervace, tak pro ověřování té zobrazené.
const _recheckSeconds = 5;

/// Nejnovější nezaplacená rezervace zákazníka (status pending/reserved,
/// payment_status unpaid), nebo null.
Future<PendingBooking?> _fetchPendingBooking(String userId) async {
  final res = await MotoGoSupabase.client
      .from('bookings')
      .select('id, status, payment_status, total_price, created_at')
      .eq('user_id', userId)
      .inFilter('status', ['reserved', 'pending'])
      .eq('payment_status', 'unpaid')
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();
  if (res == null) return null;
  return PendingBooking(
    id: res['id'] as String,
    totalPrice: (res['total_price'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.parse(res['created_at'] as String),
  );
}

/// Streams the current pending booking (if any) with a 1-second tick
/// for the countdown timer. Mirrors _checkAndShowBookingFab +
/// _startBookingFabCountdown from reservations-ui.js.
///
/// Polls the DB every [_recheckSeconds] — both while no booking is shown (so
/// a newly created one appears) and WHILE one is shown.
///
/// INCIDENT 2026-09-28 (Apple Pay, FAB svítil i po zaplacení): jakmile stream
/// rezervaci našel, tikal 30 minut z PAMĚTI a DB už se neptal. Když platbu
/// potvrdil až webhook PO tom, co appka přestala čekat na potvrzení
/// (`_showProcessingPending` → /reservations uvnitř shellu, provider se
/// nezahodil), nebo když rezervaci zaplatil/zrušil Velín či druhé zařízení,
/// FAB „Dokončit rezervaci" strašil zbývajících ~29 minut. Zaplacená /
/// zrušená / vyměněná rezervace teď FAB do 5 s shodí nebo přepne. Výpadek sítě
/// zobrazenou rezervaci NEshodí (držíme poslední známý stav) — reálně
/// rozdělaná rezervace nesmí blikat.
final pendingBookingFabProvider =
    StreamProvider.autoDispose<PendingBooking?>((ref) async* {
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    yield null;
    return;
  }

  PendingBooking? booking;
  while (true) {
    try {
      booking = await _fetchPendingBooking(user.id);
    } catch (_) {
      // Network error: keep the last known booking (if still valid), otherwise
      // wait and retry.
      if (booking == null || booking.isExpired) {
        yield null;
        await Future.delayed(const Duration(seconds: _recheckSeconds));
        continue;
      }
    }

    if (booking == null || booking.isExpired) {
      yield null;
      // No pending booking — re-check in 5 s
      await Future.delayed(const Duration(seconds: _recheckSeconds));
      continue;
    }

    // Tick every second for the countdown; after [_recheckSeconds] ticks loop
    // back and ask the DB again (paid / cancelled → FAB disappears).
    var ticks = 0;
    while (!booking.isExpired && ticks < _recheckSeconds) {
      yield booking;
      await Future.delayed(const Duration(seconds: 1));
      ticks++;
    }
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
