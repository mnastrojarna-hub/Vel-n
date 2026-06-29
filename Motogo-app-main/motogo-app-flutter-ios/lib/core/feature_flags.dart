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
