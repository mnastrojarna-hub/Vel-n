import 'package:http/http.dart' as http;
import '../config.dart';

/// Ovládání fyzického hardwaru pobočky přes HTTP (Shelly relé na LAN).
///
/// Backend (RPC) jen vrací URL — samotné volání jde z tabletu přímo na relé
/// v lokální síti, takže otevírání funguje i bez internetu (kromě ověření kódu).
class Hardware {
  Hardware._();
  static final Hardware instance = Hardware._();

  /// Otevře dveře (sepne zámkové relé). Vrací true při HTTP 2xx.
  Future<bool> openDoor(String? relayUrl) => _fire(relayUrl);

  /// Rozsvítí světlo v konkrétní garáži.
  Future<bool> turnOnLight(String? lightUrl) => _fire(lightUrl);

  /// Spustí hudbu na celé pobočce.
  Future<bool> startMusic(String? musicUrl) => _fire(musicUrl);

  /// Zastaví hudbu (volitelné).
  Future<bool> stopMusic(String? musicOffUrl) => _fire(musicOffUrl);

  Future<bool> _fire(String? url) async {
    if (url == null || url.trim().isEmpty) return false;
    try {
      final res = await http
          .get(Uri.parse(url.trim()))
          .timeout(KioskConfig.relayTimeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
