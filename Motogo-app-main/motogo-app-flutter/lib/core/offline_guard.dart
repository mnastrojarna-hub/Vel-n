import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart' show rootNavigatorKey;
import 'supabase_client.dart';
import 'theme.dart';
import 'i18n/i18n_provider.dart';

/// Offline guard — mirrors OfflineGuard from offline-guard.js.
/// Checks internet connectivity and shows overlay when offline.
class OfflineGuard {
  OfflineGuard._();

  static final _connectivity = Connectivity();
  static StreamSubscription? _subscription;

  /// Quick sync check — navigator.onLine equivalent.
  /// connectivity_plus 6+ vrací List<ConnectivityResult> (zařízení může mít
  /// víc aktivních spojení najednou) — offline = seznam obsahuje jen `none`.
  static Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Real async ping to Supabase REST endpoint.
  static Future<bool> pingSupabase() async {
    try {
      final response = await http.head(
        Uri.parse('${MotoGoSupabase.url}/rest/v1/'),
        headers: {'apikey': MotoGoSupabase.anonKey},
      ).timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Start watching connectivity changes.
  static void startWatching(BuildContext context) {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      if (result.contains(ConnectivityResult.none)) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
  }

  /// Stop watching.
  static void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Guard for important actions (login, booking, payment).
  static Future<bool> requireOnline(BuildContext context) async {
    final online = await isOnline();
    if (!online) {
      _showOverlay();
      return false;
    }
    return true;
  }

  static OverlayEntry? _overlayEntry;

  /// Root overlay spravovany hlavnim navigatorem. Drive se bralo
  /// `Overlay.of(context)` z navigatoroveho contextu — jenze navigatoruv
  /// Overlay je jeho POTOMEK, ne predek, takze lookup nahoru nic nenasel a
  /// `Overlay.of` hodil „Null check operator used on a null value". Bereme ho
  /// primo z `NavigatorState.overlay`, ktery je vzdy ten spravny.
  static OverlayState? get _overlay => rootNavigatorKey.currentState?.overlay;

  static void _showOverlay() {
    if (_overlayEntry != null) return;
    final overlay = _overlay;
    if (overlay == null || !overlay.mounted) return; // appka jeste/uz nestoji
    _overlayEntry = OverlayEntry(
      builder: (ctx) => _OfflineOverlay(onRetry: _retry),
    );
    overlay.insert(_overlayEntry!);
  }

  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  static Future<void> _retry() async {
    final online = await isOnline();
    if (online) _hideOverlay();
  }
}

/// Full-screen offline overlay — mirrors the DOM overlay from offline-guard.js.
class _OfflineOverlay extends StatelessWidget {
  final VoidCallback onRetry;
  const _OfflineOverlay({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MotoGoColors.black.withValues(alpha: 0.95),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📡', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                t(context).tr('noInternet'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                t(context).tr('offlineDesc'),
                style: const TextStyle(
                  color: MotoGoColors.g400,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(t(context).tr('retryBtn')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
