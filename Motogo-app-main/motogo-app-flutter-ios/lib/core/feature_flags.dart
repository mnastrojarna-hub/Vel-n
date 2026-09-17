import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_client.dart';

/// Feature flagy řízené z Velína (tabulka `feature_flags`).
/// Doprodej v rezervaci (e-shopové doplňky) — klíč `reservation_upsell`.
/// Default OFF: dokud flag neexistuje / je vypnutý / se nenačte, doprodej se nezobrazuje.
final reservationUpsellEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('feature_flags')
        .select('enabled')
        .eq('key', 'reservation_upsell')
        .maybeSingle();
    return res != null && res['enabled'] == true;
  } catch (_) {
    return false;
  }
});

/// Žebříček jezdců v profilu — klíč `loyalty_leaderboard`.
/// Default OFF: backend data sbírá a vyhodnocuje (ranky, km z protokolů,
/// měsíční vítěz), ale anonymní žebříček mezi ostatními uživateli se
/// v appce NEZOBRAZUJE, dokud se flag ve Velíně nezapne.
final loyaltyLeaderboardEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('feature_flags')
        .select('enabled')
        .eq('key', 'loyalty_leaderboard')
        .maybeSingle();
    return res != null && res['enabled'] == true;
  } catch (_) {
    return false;
  }
});
