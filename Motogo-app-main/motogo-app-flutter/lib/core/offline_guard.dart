import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart' show rootNavigatorKey;
import 'supabase_client.dart';
import 'theme.dart';
import 'i18n/i18n_provider.dart';
import 'widgets/error_feedback.dart' show call112, callMotoGo;

/// Offline guard — mirrors OfflineGuard from offline-guard.js.
/// Checks internet connectivity and shows overlay when offline.
///
/// 2026-10-16 (požadavek majitele „nikde se nesmí zaseknout"): překryv už
/// neblokuje nouzi — nabízí Zavolat MotoGo24 / 112 (hovor jde i bez dat) a
/// „Pokračovat bez internetu" (uložené rezervace, kódy, SOS). Zkusit znovu
/// ukáže výsledek. Wi-Fi bez internetu (captive portal) hlásí tenký pruh.
class OfflineGuard {
  OfflineGuard._();

  static final _connectivity = Connectivity();
  static StreamSubscription? _subscription;

  /// Připojení je zpět → znovu načíst data, která zůstala v chybě
  /// (nastavuje main.dart → `recoverFailedProviders`).
  static void Function()? onBackOnline;

  /// connectivity_plus 6+ vrací List<ConnectivityResult> (zařízení může mít
  /// víc aktivních spojení najednou) — offline = seznam obsahuje jen `none`.
  static bool _isNone(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.none);

  /// Quick sync check — navigator.onLine equivalent.
  static Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return !_isNone(result);
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
      if (_isNone(result)) {
        _showOverlay();
      } else {
        _hideOverlay();
        _dismissed = false;
        _checkReachable();
      }
    });
    // Start appky bez připojení → stream nemusí nic vyslat.
    isOnline().then((online) {
      if (!online) {
        _showOverlay();
      } else {
        _checkReachable();
      }
    }).catchError((_) {});
  }

  /// Stop watching.
  static void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    _pingTimer?.cancel();
  }

  /// Guard for important actions (login, booking, payment).
  static Future<bool> requireOnline(BuildContext context) async {
    final online = await isOnline();
    if (!online) {
      _dismissed = false;
      _showOverlay();
      return false;
    }
    return true;
  }

  static OverlayEntry? _overlayEntry;
  static OverlayEntry? _bannerEntry;
  static bool _dismissed = false;
  static Timer? _pingTimer;
  static int _pingFails = 0;

  /// Root overlay spravovany hlavnim navigatorem. Drive se bralo
  /// `Overlay.of(context)` z navigatoroveho contextu — jenze navigatoruv
  /// Overlay je jeho POTOMEK, ne predek, takze lookup nahoru nic nenasel a
  /// `Overlay.of` hodil „Null check operator used on a null value". Bereme ho
  /// primo z `NavigatorState.overlay`, ktery je vzdy ten spravny.
  static OverlayState? get _overlay => rootNavigatorKey.currentState?.overlay;

  static void _showOverlay() {
    if (_dismissed) {
      _showBanner(offline: true);
      return;
    }
    if (_overlayEntry != null) return;
    final overlay = _overlay;
    if (overlay == null || !overlay.mounted) return; // appka jeste/uz nestoji
    _hideBanner();
    _overlayEntry = OverlayEntry(
      builder: (ctx) => _OfflineOverlay(onRetry: _retry, onContinue: _continueOffline),
    );
    overlay.insert(_overlayEntry!);
  }

  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _hideBanner();
  }

  /// „Pokračovat bez internetu" / systémové zpět — uložené údaje a SOS
  /// zůstávají dostupné; nahoře zůstane tenký pruh „Jsi offline".
  static void _continueOffline() {
    _dismissed = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _showBanner(offline: true);
  }

  /// true = připojení je zpět (překryv zmizí).
  static Future<bool> _retry() async {
    final online = await isOnline();
    if (online) {
      _hideOverlay();
      _checkReachable();
    }
    return online;
  }

  /// Wi-Fi / data hlásí spojení, ale internet nejde (captive portal, mrtvá
  /// data) → po dvou neúspěšných pingách pruh nahoře; při úspěchu zmizí.
  static void _checkReachable() {
    _pingTimer?.cancel();
    _pingFails = 0;
    Future<void> tick() async {
      final ok = await pingSupabase();
      if (ok) {
        _pingFails = 0;
        _hideBanner();
        _pingTimer?.cancel();
        try {
          onBackOnline?.call();
        } catch (_) {}
        return;
      }
      _pingFails++;
      if (_pingFails >= 2 && _overlayEntry == null) _showBanner(offline: false);
      _pingTimer?.cancel();
      _pingTimer = Timer(Duration(seconds: _pingFails >= 2 ? 20 : 5), tick);
    }

    tick();
  }

  static bool _bannerOffline = true;

  static void _showBanner({required bool offline}) {
    _bannerOffline = offline;
    if (_bannerEntry != null) {
      _bannerEntry!.markNeedsBuild();
      return;
    }
    final overlay = _overlay;
    if (overlay == null || !overlay.mounted) return;
    _bannerEntry = OverlayEntry(builder: (ctx) => _OfflineBanner(offline: _bannerOffline));
    overlay.insert(_bannerEntry!);
  }

  static void _hideBanner() {
    _bannerEntry?.remove();
    _bannerEntry = null;
  }
}

/// Full-screen offline overlay — mirrors the DOM overlay from offline-guard.js.
class _OfflineOverlay extends StatefulWidget {
  final Future<bool> Function() onRetry;
  final VoidCallback onContinue;
  const _OfflineOverlay({required this.onRetry, required this.onContinue});

  @override
  State<_OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<_OfflineOverlay> {
  bool _checking = false;
  bool _stillOffline = false;

  Future<void> _retry() async {
    setState(() {
      _checking = true;
      _stillOffline = false;
    });
    final ok = await widget.onRetry();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _stillOffline = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // Systémové zpět překryv zavře (jako „Pokračovat bez internetu") — dřív
    // šlo „zpět" na skrytou obrazovku pod ním a překryv zůstal.
    return BackButtonListener(
      onBackButtonPressed: () async {
        widget.onContinue();
        return true;
      },
      child: Material(
        color: MotoGoColors.black.withValues(alpha: 0.95),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📡', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    tr.tr('eoOfflineTitle'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr.tr('eoOfflineGuardBody'),
                    style: const TextStyle(color: MotoGoColors.g400, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  if (_stillOffline) ...[
                    const SizedBox(height: 12),
                    Text(tr.tr('eoStillOffline'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: MotoGoColors.amberBorder,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _checking ? null : _retry,
                      child: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr.tr('retryBtn')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: MotoGoColors.g400)),
                      onPressed: widget.onContinue,
                      child: Text(tr.tr('eoContinueOffline')),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(tr.tr('eoOfflineEmergency'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: MotoGoColors.g400, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    TextButton(
                      onPressed: callMotoGo,
                      child: Text('📞 ${tr.tr('eoCallNonstop')}',
                          style: const TextStyle(
                              color: MotoGoColors.green, fontWeight: FontWeight.w800)),
                    ),
                    TextButton(
                      onPressed: call112,
                      child: const Text('🆘 112',
                          style: TextStyle(
                              color: MotoGoColors.red, fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tenký pruh nahoře: offline (uložené údaje) / internet nefunguje. Nic
/// neblokuje — dotyky jdou skrz na obrazovku pod ním.
class _OfflineBanner extends StatelessWidget {
  final bool offline;
  const _OfflineBanner({required this.offline});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 2,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: MotoGoColors.amber,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                '📡 ${tr.tr(offline ? 'eoOfflineBanner' : 'eoNoInternetBanner')}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
