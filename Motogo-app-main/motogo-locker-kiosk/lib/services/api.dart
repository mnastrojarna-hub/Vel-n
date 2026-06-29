import 'package:supabase_flutter/supabase_flutter.dart';
import 'kiosk_storage.dart';

/// Jedny dveře vrácené z backendu (relé + světlo).
class DoorInfo {
  final String? id;
  final String? kind; // motorcycle / accessories
  final int? boxNumber;
  final String? label;
  final String? relayUrl;
  final String? lightUrl;

  DoorInfo({this.id, this.kind, this.boxNumber, this.label, this.relayUrl, this.lightUrl});

  factory DoorInfo.fromMap(Map m) => DoorInfo(
        id: m['id'] as String?,
        kind: m['door_kind'] as String?,
        boxNumber: m['box_number'] as int?,
        label: m['label'] as String?,
        relayUrl: m['relay_url'] as String?,
        lightUrl: m['light_url'] as String?,
      );

  String get displayName {
    if (label != null && label!.isNotEmpty) return label!;
    if (kind == 'accessories') return 'Oblečení';
    if (boxNumber != null) return 'Garáž #$boxNumber';
    return 'Dveře';
  }
}

/// Výsledek ověření kódu RPC kiosk_resolve_code.
class ResolveResult {
  final bool ok;
  final String? error;
  final String kind; // motorcycle / accessories / service
  final String? bookingId;
  final int? boxNumber;
  final String? musicOnUrl;
  final String? musicOffUrl;
  final int musicSeconds;
  final int doorOpenSeconds;
  final int lightSeconds;
  final DoorInfo? door;
  final List<DoorInfo> doors;
  final bool doorConfigured;

  ResolveResult({
    required this.ok,
    this.error,
    this.kind = '',
    this.bookingId,
    this.boxNumber,
    this.musicOnUrl,
    this.musicOffUrl,
    this.musicSeconds = 90,
    this.doorOpenSeconds = 8,
    this.lightSeconds = 120,
    this.door,
    this.doors = const [],
    this.doorConfigured = false,
  });

  bool get isService => kind == 'service';

  factory ResolveResult.fromMap(Map m) {
    final doorMap = m['door'];
    final doorsList = (m['doors'] as List?) ?? const [];
    return ResolveResult(
      ok: m['ok'] == true,
      error: m['error'] as String?,
      kind: (m['kind'] as String?) ?? '',
      bookingId: m['booking_id'] as String?,
      boxNumber: m['box_number'] as int?,
      musicOnUrl: m['music_on_url'] as String?,
      musicOffUrl: m['music_off_url'] as String?,
      musicSeconds: (m['music_seconds'] as int?) ?? 90,
      doorOpenSeconds: (m['door_open_seconds'] as int?) ?? 8,
      lightSeconds: (m['light_seconds'] as int?) ?? 120,
      door: doorMap is Map ? DoorInfo.fromMap(doorMap) : null,
      doors: doorsList.whereType<Map>().map((d) => DoorInfo.fromMap(d)).toList(),
      doorConfigured: m['door_configured'] == true,
    );
  }
}

/// Komunikace s backendem (Supabase RPC) — autentizace per zařízení.
class KioskApi {
  KioskApi._();
  static final KioskApi instance = KioskApi._();

  SupabaseClient get _sb => Supabase.instance.client;
  KioskStorage get _store => KioskStorage.instance;

  Map<String, dynamic> get _auth => {
        'p_device_id': _store.deviceId,
        'p_device_token': _store.deviceToken,
      };

  /// Heartbeat — online stav + verze + konfigurace pobočky. Vrací branch_name.
  Future<Map?> heartbeat({String? appVersion, String? platform}) async {
    try {
      final res = await _sb.rpc('kiosk_heartbeat', params: {
        ..._auth,
        'p_app_version': appVersion,
        'p_platform': platform,
      });
      if (res is Map && res['ok'] == true) {
        final name = res['branch_name'] as String?;
        if (name != null && name.isNotEmpty) await _store.setBranchName(name);
        return res;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Ověří kód → vrátí které dveře otevřít.
  Future<ResolveResult> resolveCode(String code) async {
    try {
      final res = await _sb.rpc('kiosk_resolve_code', params: {..._auth, 'p_code': code});
      if (res is Map) return ResolveResult.fromMap(res);
      return ResolveResult(ok: false, error: 'bad_response');
    } catch (e) {
      return ResolveResult(ok: false, error: 'network');
    }
  }

  /// Audit otevření (best-effort).
  Future<void> logOpen({
    String? doorId,
    required String kind,
    String? bookingId,
    required bool success,
    Map<String, dynamic> detail = const {},
  }) async {
    try {
      await _sb.rpc('kiosk_log_open', params: {
        ..._auth,
        'p_door_id': doorId,
        'p_kind': kind,
        'p_booking_id': bookingId,
        'p_success': success,
        'p_detail': detail,
      });
    } catch (_) {}
  }

  /// Stáhne čekající vzdálené příkazy (token-ověřeno).
  Future<List<Map>> fetchCommands() async {
    try {
      final res = await _sb.rpc('kiosk_fetch_commands', params: _auth);
      if (res is Map && res['ok'] == true) {
        return ((res['commands'] as List?) ?? const []).whereType<Map>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Nahlásí výsledek vzdáleného příkazu z Velína.
  Future<void> completeCommand(String commandId, bool success, {Map<String, dynamic> result = const {}}) async {
    try {
      await _sb.rpc('kiosk_complete_command', params: {
        ..._auth,
        'p_command_id': commandId,
        'p_success': success,
        'p_result': result,
      });
    } catch (_) {}
  }

  /// Ověření párovacích údajů při Setupu (heartbeat = ok znamená platné).
  Future<String?> validatePairing(String deviceId, String token) async {
    try {
      final res = await _sb.rpc('kiosk_heartbeat', params: {
        'p_device_id': deviceId.trim(),
        'p_device_token': token.trim(),
      });
      if (res is Map && res['ok'] == true) return null;
      return 'Neplatné ID zařízení nebo token.';
    } catch (e) {
      return 'Chyba spojení se serverem.';
    }
  }
}
