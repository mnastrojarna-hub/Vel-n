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

/// Přistavení / odvoz na adresu u motorek ze SAMOOBSLUŽNÉ pobočky — klíč
/// `self_service_delivery` (rozhodnutí majitele 2026-09-28). Default OFF:
/// rezervační formulář i úprava rezervace nabízí u samoobsluhy jen pobočku,
/// volby na adresu zůstávají vidět zabalené s vysvětlením; zapnutí ve Velíně
/// (Texty webu → Feature flags) je zpřístupní. Stejný flag čte web i DB trigger.
final selfServiceDeliveryEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('feature_flags')
        .select('enabled')
        .eq('key', 'self_service_delivery')
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
