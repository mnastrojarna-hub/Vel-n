import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
        _showOverlay(context);
      } else {
        _hideOverlay(context);
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
      _showOverlay(context);
      return false;
    }
    return true;
  }

  static OverlayEntry? _overlayEntry;

  static void _showOverlay(BuildContext context) {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (ctx) => _OfflineOverlay(onRetry: () => _retry(context)),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  static void _hideOverlay(BuildContext context) {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  static Future<void> _retry(BuildContext context) async {
    final online = await isOnline();
    if (online) _hideOverlay(context);
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
              const Text(
                'Pro používání MotoGo24 je potřeba připojení k internetu.\n'
                'Zkontrolujte Wi-Fi nebo mobilní data.',
                style: TextStyle(
                  color: MotoGoColors.g400,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('ZKUSIT ZNOVU'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
