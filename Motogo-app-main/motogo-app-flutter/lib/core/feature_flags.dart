import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pending_booking_fab_provider.dart' show paymentProcessingProvider;
import 'supabase_client.dart';
import 'v2/flag/v2_scope.dart' show kV2TabRoots;

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

/// E-shop v menu Profilu — klíč `eshop_visible` (zadání majitele 2026-10-01:
/// e-shop dočasně skrytý, na jeho místě „Pobočky“). Default OFF: chybějící
/// řádek / chyba = skrytý. Stejný flag čte web (hlavní menu + patička).
final eshopVisibleProvider = FutureProvider<bool>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('feature_flags')
        .select('enabled')
        .eq('key', 'eshop_visible')
        .maybeSingle();
    return res != null && res['enabled'] == true;
  } catch (_) {
    return false;
  }
});

/// Nový vzhled appky (v2) — klíč `app_v2_ui` = KILL-SWITCH majitele
/// (2026-10-16): chybějící řádek / `enabled = true` = ZAPNUTO, `enabled =
/// false` = okamžitý návrat ke starému vzhledu BEZ vydání nové verze.
/// Vrací null, když se flag nepodařilo načíst (offline, timeout) — pak platí
/// poslední známá hodnota (pref `mg_app_v2_ui`), při prvním spuštění ZAPNUTO.
Future<bool?> fetchAppV2UiFlag() async {
  try {
    final res = await MotoGoSupabase.client
        .from('feature_flags')
        .select('enabled')
        .eq('key', 'app_v2_ui')
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    if (res == null) return true;
    return res['enabled'] != false;
  } catch (_) {
    return null;
  }
}

/// Stav přepínače v2 vzhledu. Změna se NIKDY neprojeví uprostřed toku
/// (platba, rezervace, úprava): nová hodnota z DB se uloží do prefu (platí od
/// příštího studeného startu) a do [pending]; hned se použije jen v bezpečný
/// okamžik — na kořeni záložky a mimo běžící platbu ([applyPendingIfSafe]).
class AppV2UiNotifier extends StateNotifier<bool> {
  static const prefKey = 'mg_app_v2_ui';

  /// Hodnota pro studený start (načtená [preload] před `runApp`).
  static bool bootValue = true;

  /// Přečte poslední známou hodnotu z prefu (chybí → ZAPNUTO).
  static Future<void> preload() async {
    try {
      final p = await SharedPreferences.getInstance();
      bootValue = p.getBool(prefKey) ?? true;
    } catch (_) {
      bootValue = true;
    }
  }

  final Future<bool?> Function() _fetch;
  final bool Function() _paymentRunning;

  /// Hodnota z DB, která čeká na bezpečný okamžik (null = nic nečeká).
  bool? pending;

  AppV2UiNotifier({
    Future<bool?> Function()? fetch,
    bool Function()? paymentRunning,
    bool autoRefresh = true,
    bool? initial,
  })  : _fetch = fetch ?? fetchAppV2UiFlag,
        _paymentRunning = paymentRunning ?? (() => false),
        super(initial ?? bootValue) {
    if (autoRefresh) unawaited(refresh());
  }

  /// Načte flag z DB; neznámý výsledek (offline) nic nemění.
  Future<void> refresh() async {
    final remote = await _fetch();
    if (remote == null || !mounted) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefKey, remote);
    } catch (_) {}
    if (!mounted) return;
    pending = remote == state ? null : remote;
  }

  /// Použije čekající hodnotu, pokud je [location] kořen záložky a neběží
  /// platba. Vrací true, když se vzhled přepnul.
  bool applyPendingIfSafe(String location) {
    final p = pending;
    if (p == null || !mounted) return false;
    if (_paymentRunning()) return false;
    final path = Uri.tryParse(location)?.path ?? location;
    if (!kV2TabRoots.contains(path)) return false;
    pending = null;
    state = p;
    return true;
  }
}

/// true = v2 vzhled (čte `MgV2Scope` v `MaterialApp.builder`).
final appV2UiProvider = StateNotifierProvider<AppV2UiNotifier, bool>(
  (ref) => AppV2UiNotifier(
    paymentRunning: () => ref.read(paymentProcessingProvider),
  ),
);
