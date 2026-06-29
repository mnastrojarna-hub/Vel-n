import 'api.dart';

/// Vzdálená diagnostika — kiosk hlásí chyby/pády/události do Velína (kiosk_logs).
class KioskDiag {
  KioskDiag._();
  static String? appVersion;

  static Future<void> log(String level, String source, String message,
          [Map<String, dynamic> detail = const {}]) =>
      KioskApi.instance.logEvent(
        level: level, source: source, message: message, detail: detail, appVersion: appVersion,
      );

  static Future<void> info(String source, String message, [Map<String, dynamic> d = const {}]) => log('info', source, message, d);
  static Future<void> warn(String source, String message, [Map<String, dynamic> d = const {}]) => log('warn', source, message, d);
  static Future<void> error(String source, String message, [Map<String, dynamic> d = const {}]) => log('error', source, message, d);
  static Future<void> crash(String source, String message, [Map<String, dynamic> d = const {}]) => log('crash', source, message, d);
}
