import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import 'reservation_provider.dart';

/// Brána samoobslužné pobočky k rezervaci (Velké Němčice, 2026-10-04) —
/// RPC `get_booking_gate_info(p_booking_id)` (jen vlastník rezervace).
/// [gateCode] = kód schránky s klíčem od brány; server ho vrací až s VYDANÝM
/// kódem motorky u reserved/active rezervace (jinak null). Kód nikdy natvrdo
/// v appce. [lockerDoor] = číslo dveří šatny (null = neznámé).
class BookingGateInfo {
  final bool hasGate;
  final String? gateCode;
  final int? lockerDoor;
  const BookingGateInfo({this.hasGate = false, this.gateCode, this.lockerDoor});

  static const none = BookingGateInfo();

  factory BookingGateInfo.fromJson(Object? raw) {
    if (raw is! Map) return none;
    final code = raw['gate_code']?.toString().trim();
    final door = raw['locker_door'];
    return BookingGateInfo(
      hasGate: raw['has_gate'] == true,
      gateCode: (code == null || code.isEmpty) ? null : code,
      lockerDoor: door is num ? door.toInt() : int.tryParse('${door ?? ''}'),
    );
  }
}

/// Info o bráně pro detail rezervace (karta kódů + postup při vyzvednutí).
/// Starý backend bez RPC / chyba / offline → „bez brány“ (nic se nerozbije).
/// Znovu se načte, jakmile se vydá kód motorky (kód brány jde s ním) —
/// sleduje jen tenhle příznak, ne každé obnovení kódů.
final bookingGateInfoProvider = FutureProvider.autoDispose
    .family<BookingGateInfo, String>((ref, bookingId) async {
  ref.watch(doorCodesProvider(bookingId).select((v) =>
      v.valueOrNull?.any((c) => c.codeType == 'motorcycle' && c.sentToCustomer) ?? false));
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_booking_gate_info', params: {'p_booking_id': bookingId});
    return BookingGateInfo.fromJson(res);
  } catch (_) {
    return BookingGateInfo.none;
  }
});
