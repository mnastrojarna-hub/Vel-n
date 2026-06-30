import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'api.dart';

/// Stahuje stav ostrovní FV elektrárny z lokálního měniče (HTTP/JSON na LAN)
/// a posílá ho do Supabase přes kiosk_report_power. Velín pak stav zobrazuje.
///
/// URL a interval přicházejí z kiosk_heartbeat (konfigurace pobočky ve Velíně).
class PowerPoller {
  PowerPoller._();
  static final PowerPoller instance = PowerPoller._();

  Timer? _timer;
  String? _url;
  int _seconds = 60;

  /// Nastaví poller dle konfigurace z heartbeatu. Restartuje jen při změně.
  void configure(String? url, int seconds) {
    final u = (url ?? '').trim();
    final s = seconds < 15 ? 15 : seconds;
    if (u.isEmpty) {
      stop();
      return;
    }
    if (u == _url && s == _seconds && _timer != null) return;
    _url = u;
    _seconds = s;
    _timer?.cancel();
    _tick();
    _timer = Timer.periodic(Duration(seconds: _seconds), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _url = null;
  }

  Future<void> _tick() async {
    final url = _url;
    if (url == null) return;
    try {
      final res = await http.get(Uri.parse(url)).timeout(KioskConfig.relayTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        await KioskApi.instance.reportPower(decoded);
      } else if (decoded is Map) {
        await KioskApi.instance.reportPower(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {/* offline / nevalidní JSON — přeskoč */}
  }
}
