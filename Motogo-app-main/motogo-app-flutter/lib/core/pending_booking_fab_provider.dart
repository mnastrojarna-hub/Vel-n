import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'paid_change_queue.dart';
import 'payment_pending_marker.dart';
import 'supabase_client.dart';
import '../features/payment/paid_change_api.dart' show piIdFromClientSecret;
import '../features/payment/payment_verify.dart' show verifyPayment, VerifyState;
import '../features/payment/stripe_service.dart'
    show StripeService, NextActionOutcome;

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

/// True, dokud PaymentScreen čeká na výsledek platby (stržení karty, 3DS,
/// potvrzení serverem). AppShell pak záložkou spodní lišty neodvede zákazníka
/// pryč bez potvrzení — ztracený výsledek vedl k opakované (dvojí) platbě.
final paymentProcessingProvider = StateProvider<bool>((ref) => false);

/// Co udělat, když zákazník z běžící platby přesto odejde záložkou (po
/// potvrzení). E-shop: „Platba se ověřuje" místo plného košíku — jinak by
/// nová objednávka vedla k druhé platbě. null = jen přejít na záložku.
final paymentLeaveActionProvider = StateProvider<void Function()?>((ref) => null);

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
  /// Platba už byla odeslána a čeká se na potvrzení (lokální značka) — FAB
  /// pak NEnabízí další platbu, jen „Platba se ověřuje".
  final bool verifying;

  const PendingBooking({
    required this.id,
    required this.totalPrice,
    required this.createdAt,
    this.verifying = false,
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

/// Začátek okna na zaplacení: pozdější z vytvoření a obnovení rezervace.
DateTime pendingWindowStart(String createdAt, String? restoredAt) {
  final c = DateTime.parse(createdAt);
  final r = restoredAt == null ? null : DateTime.tryParse(restoredAt);
  return r != null && r.isAfter(c) ? r : c;
}

/// Jak často se DB ptáme, jestli rezervace (ještě) čeká na platbu — sekundy.
/// Platí jak pro hledání nové rezervace, tak pro ověřování té zobrazené.
const _recheckSeconds = 5;

/// Nejnovější nezaplacená rezervace zákazníka (status pending/reserved,
/// payment_status unpaid), nebo null.
Future<PendingBooking?> _fetchPendingBooking(String userId) async {
  final res = await MotoGoSupabase.client
      .from('bookings')
      .select('id, status, payment_status, total_price, created_at, restored_at')
      .eq('user_id', userId)
      .inFilter('status', ['reserved', 'pending'])
      .eq('payment_status', 'unpaid')
      // Jen app rezervace: webová čeká na bankovní převod (QR) — nabídnout
      // k ní platbu kartou by vedlo k dvojí platbě.
      .eq('booking_source', 'app')
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle()
      .timeout(const Duration(seconds: 10));
  if (res == null) return null;
  final id = res['id'] as String;
  return PendingBooking(
    id: id,
    totalPrice: (res['total_price'] as num?)?.toDouble() ?? 0,
    // Obnovená rezervace (D3) má nové 30min okno od obnovy (server
    // auto_cancel_expired_pending počítá od restored_at).
    createdAt: pendingWindowStart(res['created_at'] as String, res['restored_at'] as String?),
    verifying: await PaymentPendingMarker.isPending(id) ||
        await _expiredIntentStillRunning(id),
  );
}

/// Značka „platba odeslána" vypršela (15 min), ale PaymentIntent posledního
/// pokusu známe → zeptat se Stripe, než FAB nabídne DALŠÍ platbu. Prošla /
/// banka ji ještě zpracovává / stav nejde zjistit → „Platba se ověřuje"
/// (značku obnovíme, ať se Stripe neptáme každých 5 s); zamítnutá /
/// nedokončená → značku smazat a platbu nabídnout.
Future<bool> _expiredIntentStillRunning(String id) async {
  final cs = await PaymentPendingMarker.expiredIntent(id);
  if (cs == null) return false;
  final o = StripeService.outcomeForStatus(await StripeService.fetchIntentStatus(cs));
  if (o == NextActionOutcome.failed || o == NextActionOutcome.notCompleted) {
    await PaymentPendingMarker.clear(id);
    return false;
  }
  await PaymentPendingMarker.set(id);
  return true;
}

/// Platba odeslaná před zabitím / pádem appky, která se mezitím potvrdila.
class PaidAfterRestart {
  final String bookingId;
  /// [PaymentMarkerKind] — určuje text oznámení (rezervace ≠ doplatek úpravy).
  final String kind;
  const PaidAfterRestart(this.bookingId, this.kind);
}

/// Po startu appky: platba odeslaná před zabitím / pádem appky (lokální
/// značka) — výsledek ověřený podle DRUHU platby. Vrací rezervaci, jejíž
/// platba je mezitím prokazatelně zaplacená (AppShell to jednou oznámí),
/// jinak null. Zrušené / neznámé značky uklidí.
///
/// Doplatek úpravy / výměny motorky běží nad UŽ ZAPLACENOU rezervací
/// (`payment_status` = 'paid' z původní platby) → rozhoduje nová cena
/// (úprava) nebo stav PaymentIntentu (výměna, SOS). Dokud výsledek neznáme,
/// značka zůstává (žádné falešné „zaplaceno", žádný druhý doplatek).
final paidAfterRestartProvider =
    FutureProvider.autoDispose<PaidAfterRestart?>((ref) async {
  if (MotoGoSupabase.currentUser == null) return null;
  final markers = await PaymentPendingMarker.pendingMarkers();
  // D6: zaplacený doplatek výměny / úpravy, jehož zápis appka nestihla (zabití
  // appky, výpadek sítě) → do trvalé fronty a dokončit přes server.
  for (final m in markers) {
    if (m.kind != PaymentMarkerKind.edit && m.kind != PaymentMarkerKind.swap) continue;
    final pi = piIdFromClientSecret(m.clientSecretCurrent ? m.clientSecret : null);
    if (pi == null || await PaidChangeQueue.get(pi) != null) continue;
    await PaidChangeQueue.enqueue(PaidChangeEntry(
        key: pi, bookingId: m.id, kind: m.kind == PaymentMarkerKind.swap ? 'swap' : 'edit',
        charge: 0, paid: false));
  }
  final done = <PaidChangeEntry>[];
  final sub = PaidChangeQueue.events.listen((ev) {
    if (ev.result.status == PaidChangeStatus.done) done.add(ev.entry);
  });
  try {
    await PaidChangeQueue.drain(reason: 'start', force: true);
    await Future<void>.delayed(Duration.zero); // doručit události z běhu
  } finally {
    await sub.cancel();
  }
  if (done.isNotEmpty) {
    // Dokončeno teď → jednou oznámit („Doplatek proběhl a úprava rezervace
    // je uložená" — platí i pro výměnu motorky).
    for (final e in done) {
      await PaymentPendingMarker.clear(e.bookingId);
    }
    return PaidAfterRestart(done.first.bookingId, PaymentMarkerKind.edit);
  }
  for (final m in markers) {
    try {
      switch (m.kind) {
        case PaymentMarkerKind.order:
          continue; // objednávku e-shopu ověřuje košík / „Platba se ověřuje"
        case PaymentMarkerKind.edit:
        case PaymentMarkerKind.swap:
        case PaymentMarkerKind.sos:
          final byTotal = m.kind == PaymentMarkerKind.edit && m.expectedTotal != null;
          final st = await verifyPayment(
            bookingId: m.id,
            expectedTotal: byTotal ? m.expectedTotal : null,
            intentOnly: !byTotal,
          );
          if (st == VerifyState.paid) return PaidAfterRestart(m.id, m.kind);
          continue;
        default:
          final row = await MotoGoSupabase.client
              .from('bookings')
              .select('status, payment_status')
              .eq('id', m.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 10));
          if (row == null) continue; // cizí id — nechat doběhnout
          if (row['payment_status'] == 'paid') {
            await PaymentPendingMarker.clear(m.id);
            return PaidAfterRestart(m.id, PaymentMarkerKind.booking);
          }
          if (row['status'] == 'cancelled') await PaymentPendingMarker.clear(m.id);
      }
    } catch (_) {/* offline — zkusí se při dalším startu */}
  }
  return null;
});

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
/// [reason] = interní důvod pro Velín (vypršení času / nový pokus o platbu).
Future<void> cancelPendingBooking(String bookingId,
    {String reason = 'Zákazník si to rozmyslel'}) async {
  await MotoGoSupabase.client.from('bookings').update({
    'status': 'cancelled',
    'cancelled_by_source': 'customer',
    'cancellation_reason': reason,
    'cancelled_at': DateTime.now().toIso8601String(),
  }).eq('id', bookingId).eq('payment_status', 'unpaid')
      .timeout(const Duration(seconds: 15));
}
