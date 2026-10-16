import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import '../catalog/catalog_provider.dart';
import 'reservation_models.dart';

/// Booking select query — matches _getBookingById from reservations-ui.js.
const _bookingSelect =
    '*, motorcycles!moto_id(*, branches(name, address, city, gps_lat, gps_lng, type))';

/// Funkční odkaz „napsat recenzi na Googlu“ (shodný s `app_settings.google_review_url`
/// a s výchozí hodnotou edge fn `send-booking-email`). Starý krátký tvar
/// `g.page/MotoGo24/review` Google zrušil — nepoužívat.
const kGoogleReviewFallbackUrl = 'https://g.page/r/CUmeYvk-sNf6EBM/review';

/// Recenze z appky vedou VÝHRADNĚ na Google (zadání majitele 2026-10-15) —
/// hodnota z DB mimo doménu Googlu se ignoruje a použije se [kGoogleReviewFallbackUrl].
/// Pravidlo shodné s edge `_shared/review-links.ts` (`isGoogleReviewUrl`).
bool isGoogleReviewUrl(String url) {
  final u = Uri.tryParse(url.trim());
  final host = u?.host.toLowerCase() ?? '';
  // Zrušené vlastní krátké názvy (g.page/<jméno>/review) Google neobsluhuje —
  // platné jsou jen g.page/r/<id>.
  if (host == 'g.page') return u!.path.startsWith('/r/');
  // maps.app.goo.gl/…, (search|www|maps).google.<tld>[.<cc>]/…
  return host == 'goo.gl' || host.endsWith('.goo.gl') ||
      RegExp(r'(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$').hasMatch(host);
}

/// Odkaz na Google recenze — čte se ze stejného zdroje jako e-mailové šablony
/// (`app_settings.google_review_url`), aby appka i mail vedly na FUNKČNÍ odkaz.
final googleReviewUrlProvider = FutureProvider<String>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('app_settings')
        .select('value')
        .eq('key', 'google_review_url')
        .maybeSingle();
    final v = res?['value'];
    final url = (v is String
        ? v
        : (v is Map ? (v['url'] as String?) : null))?.trim();
    if (url != null && url.startsWith('https://') && isGoogleReviewUrl(url)) return url;
  } catch (_) {/* fallback */}
  return kGoogleReviewFallbackUrl;
});

/// Fetches all user bookings with realtime subscription.
/// Mirrors apiFetchMyBookings() + realtime channel.
final reservationsProvider =
    StreamProvider<List<Reservation>>((ref) async* {
  // Motorka rezervace (pobočka, kóje, stav) se může změnit i bez změny řádku
  // bookings (přesun motorky ve Velíně) → po realtime změně motorek načíst znovu.
  ref.listen(motorcyclesProvider, (prev, next) {
    if (prev != null && next.hasValue) ref.invalidateSelf();
  });
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    yield [];
    return;
  }

  // Initial fetch
  final initial = await _fetchBookings(user.id);
  yield initial;

  // Realtime subscription — bookings table changes for this user.
  // Transport errors (lost connection, channel restart) must NOT bubble up
  // as an AsyncError — the initial fetch above already produced valid data
  // and we don't want a network blip to wipe the UI or trigger a logout.
  try {
    await for (final _ in MotoGoSupabase.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)) {
      yield await _fetchBookings(user.id);
    }
  } catch (e) {
    if (await handleAuthError(e)) return;
    // Non-auth failure (ChannelError, network, etc.) — stop live updates
    // silently; user keeps seeing the last fetched list.
    return;
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

/// True when the user currently has a binding rental in progress — an active
/// rental (today within the booked range) or an upcoming, already-paid one.
/// During this window consents and core permissions are required by the rental
/// terms (mirrors the door-code / contract obligations), so the UI locks them.
final hasActiveReservationProvider = Provider<bool>((ref) {
  final list = ref.watch(reservationsProvider).valueOrNull ?? const [];
  return list.any((r) {
    // Kalendářně běžící termín (i před vydáním motorky — displayStatus je
    // do podpisu protokolu „Nadcházející“, zámek má ale platit celý termín).
    if (r.inRentalTerm) return true;
    if (r.displayStatus == ResStatus.nadchazejici && r.paymentStatus == 'paid') return true;
    return false;
  });
});

/// Single reservation by ID.
final reservationByIdProvider =
    FutureProvider.family<Reservation?, String>((ref, id) async {
  // Přesun motorky (pobočka/kóje) → detail rezervace se obnoví hned.
  ref.listen(motorcyclesProvider, (prev, next) {
    if (prev != null && next.hasValue) ref.invalidateSelf();
  });
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
/// Stream je jen podnět k obnovení: RLS (2026-10-10) pouští zákazníkovi jen
/// VYDANÉ kódy, stav zadržených (bez čísla) čte `_fetchDoorCodes` přes RPC.
final doorCodesProvider =
    StreamProvider.family<List<DoorCode>, String>((ref, bookingId) async* {
  // Initial fetch
  yield await _fetchDoorCodes(bookingId);

  // Realtime subscription — same resilience as reservationsProvider: swallow
  // transport errors so a flaky channel doesn't blow away the door codes UI.
  try {
    await for (final _ in MotoGoSupabase.client
        .from('branch_door_codes')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)) {
      yield await _fetchDoorCodes(bookingId);
    }
  } catch (e) {
    if (await handleAuthError(e)) return;
    return;
  }
});

/// Aktivní kódy rezervace přes RPC `get_my_door_codes` — vrací i ZADRŽENÉ
/// kódy (`door_code` NULL + `withheld_reason`), které přímý select po
/// zpřísnění RLS (2026-10-10) už nevidí. Chyba RPC (starší backend) → původní
/// select tabulky.
Future<List<DoorCode>> _fetchDoorCodes(String bookingId) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_my_door_codes', params: {'p_booking_id': bookingId});
    if (res is List) {
      return res
          .whereType<Map>()
          .map((e) => DoorCode.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.isActive)
          .toList();
    }
  } catch (_) {
    // fallback níže
  }
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
  /// Číslo kódu; '' u zadrženého kódu (RPC vrací `door_code` NULL).
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

/// Výsledek storna (`cancel_booking_tracked`).
class CancelResult {
  final bool ok;
  final int refundPercent;
  final double refundAmount;
  /// Proč storno neprošlo: already | forbidden | not_found | network | failed.
  final String? error;
  const CancelResult.success(this.refundPercent, this.refundAmount)
      : ok = true,
        error = null;
  const CancelResult.failure(this.error)
      : ok = false,
        refundPercent = 0,
        refundAmount = 0;
}

/// Cancel booking via RPC — mirrors apiCancelBooking. RPC chyby NEhází, vrací
/// `{error:'…'}` (česky) — dřív je appka ignorovala a hlásila úspěch.
Future<CancelResult> cancelBooking(String bookingId, String reason) async {
  try {
    final r = await MotoGoSupabase.client.rpc('cancel_booking_tracked', params: {
      'p_booking_id': bookingId,
      'p_reason': reason,
    }).timeout(const Duration(seconds: 20));
    if (r is Map && r['success'] == true) {
      return CancelResult.success((r['refund_percent'] as num?)?.toInt() ?? 0,
          (r['refund_amount'] as num?)?.toDouble() ?? 0);
    }
    final err = r is Map ? '${r['error'] ?? ''}' : '';
    if (err.contains('stornována')) return const CancelResult.failure('already');
    if (err.contains('oprávnění')) return const CancelResult.failure('forbidden');
    if (err.contains('nenalezena')) return const CancelResult.failure('not_found');
    return const CancelResult.failure('failed');
  } catch (e) {
    final m = e.toString().toLowerCase();
    final network = e is TimeoutException ||
        m.contains('socketexception') ||
        m.contains('clientexception') ||
        m.contains('failed host lookup') ||
        m.contains('connection');
    return CancelResult.failure(network ? 'network' : 'failed');
  }
}

/// Submit rating for a completed booking.
/// Returns null on success or error message string on failure.
Future<String?> rateBooking(String bookingId, int rating) async {
  try {
    await MotoGoSupabase.client.from('bookings').update({
      'rating': rating,
      // UTC s označením zóny — bez něj by Postgres místní čas uložil jako UTC (+1–2 h).
      'rated_at': DateTime.now().toUtc().toIso8601String(),
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

  /// i18n klíč typu incidentu (UI: `t(context).tr(typeKey)`); neznámý typ
  /// se zobrazí tak, jak je.
  String get typeKey => const {
        'theft': 'theft',
        'accident_minor': 'accidentMinorLabel',
        'accident_major': 'accidentMajorLabel',
        'breakdown_minor': 'breakdownMinorLabel',
        'breakdown_major': 'breakdownMajorLabel',
        'defect_question': 'defectQuestionLabel',
        'location_share': 'shareLocation',
        'other': 'other',
      }[type] ??
      type;

  /// i18n klíč stavu incidentu.
  String get statusKey => const {
        'reported': 'reported',
        'acknowledged': 'accepted',
        'in_progress': 'inProgress',
        'resolved': 'resolved',
        'closed': 'closed',
      }[status] ??
      status;
}
