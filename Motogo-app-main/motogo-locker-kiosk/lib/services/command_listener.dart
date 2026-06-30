import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'hardware.dart';
import 'kiosk_lock.dart';
import 'kiosk_storage.dart';

/// Vzdálené ovládání z Velína.
///
/// Kiosk běží pod anon klíčem, takže nemůže číst admin-only kiosk_commands přes
/// postgres_changes. Místo toho posloucháme DB **broadcast** na neuhodnutelném
/// topicu `kiosk:<device_id>` (jen probuzení) a příkazy si bezpečně stáhneme přes
/// token-ověřenou RPC kiosk_fetch_commands. `drain()` se volá i při heartbeatu
/// (pojistka, kdyby broadcast nedorazil).
class CommandListener {
  CommandListener._();
  static final CommandListener instance = CommandListener._();

  RealtimeChannel? _channel;
  bool _draining = false;
  final Set<String> _handled = {};

  void Function(String label)? onIdentify;
  void Function()? onReload;

  void start() {
    final deviceId = KioskStorage.instance.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    stop();
    _channel = Supabase.instance.client
        .channel('kiosk:$deviceId')
        .onBroadcast(event: 'cmd', callback: (_) => drain())
        .subscribe();
    drain();
  }

  void stop() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  /// Stáhne a provede čekající příkazy (bezpečně, bez dvojího provedení).
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final commands = await KioskApi.instance.fetchCommands();
      for (final row in commands) {
        final id = row['id'] as String?;
        if (id == null || _handled.contains(id)) continue;
        _handled.add(id);
        await _execute(id, row['command'] as String?, (row['params'] as Map?) ?? const {});
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _execute(String id, String? cmd, Map params) async {
    bool ok = false;
    final Map<String, dynamic> result = {};
    try {
      switch (cmd) {
        case 'open_door':
          final music = params['music_url'] as String?;
          if ((music ?? '').isNotEmpty) Hardware.instance.startMusic(music);
          await Hardware.instance.turnOnLight(params['light_url'] as String?);
          ok = await Hardware.instance.openDoor(params['relay_url'] as String?);
          result['opened'] = ok;
          break;
        case 'music_on':
          ok = await Hardware.instance.startMusic(params['music_url'] as String?);
          break;
        case 'music_off':
          ok = await Hardware.instance.stopMusic(params['music_url'] as String?);
          break;
        case 'identify':
          onIdentify?.call((params['label'] as String?) ?? 'Velín');
          ok = true;
          break;
        case 'reload':
          onReload?.call();
          ok = true;
          break;
        case 'restart':
          ok = true;
          await KioskApi.instance.completeCommand(id, true, result: {'restarting': true});
          await KioskLock.restartApp();
          return;
        case 'camera_control':
        case 'http_get':
          ok = await Hardware.instance.httpGet(params['url'] as String?);
          break;
        default:
          result['error'] = 'unknown_command';
      }
    } catch (e) {
      result['error'] = e.toString();
    }
    await KioskApi.instance.completeCommand(id, ok, result: result);
  }
}
