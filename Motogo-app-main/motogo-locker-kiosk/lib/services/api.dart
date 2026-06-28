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
  final DoorInfo? door; // u zákaznického kódu
  final List<DoorInfo> doors; // u servisního hesla (výběr)
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

/// Komunikace s backendem (Supabase RPC).
class KioskApi {
  KioskApi._();
  static final KioskApi instance = KioskApi._();

  SupabaseClient get _sb => Supabase.instance.client;
  KioskStorage get _store => KioskStorage.instance;

  /// Ověří kód (zákaznický nebo servisní) → vrátí které dveře otevřít.
  Future<ResolveResult> resolveCode(String code) async {
    try {
      final res = await _sb.rpc('kiosk_resolve_code', params: {
        'p_branch_code': _store.branchCode,
        'p_kiosk_token': _store.token,
        'p_code': code,
      });
      if (res is Map) return ResolveResult.fromMap(res);
      return ResolveResult(ok: false, error: 'bad_response');
    } catch (e) {
      return ResolveResult(ok: false, error: 'network');
    }
  }

  /// Zapíše audit otevření (best-effort, chyba nikdy neshodí flow).
  Future<void> logOpen({
    String? doorId,
    required String kind,
    String? bookingId,
    required bool success,
    Map<String, dynamic> detail = const {},
  }) async {
    try {
      await _sb.rpc('kiosk_log_open', params: {
        'p_branch_code': _store.branchCode,
        'p_kiosk_token': _store.token,
        'p_door_id': doorId,
        'p_kind': kind,
        'p_booking_id': bookingId,
        'p_success': success,
        'p_detail': detail,
      });
    } catch (_) {/* ignore */}
  }

  /// Ověření párovacích údajů při Setupu — zkusí libovolný kód;
  /// 'unauthorized' = špatný token, 'branch_not_found' = špatný kód pobočky.
  /// Cokoliv jiného (invalid_code, missing_inputs) = párování OK.
  Future<String?> validatePairing(String branchCode, String token) async {
    try {
      final res = await _sb.rpc('kiosk_resolve_code', params: {
        'p_branch_code': branchCode.trim(),
        'p_kiosk_token': token.trim(),
        'p_code': '__pairing_check__',
      });
      if (res is Map) {
        final err = res['error'];
        if (err == 'branch_not_found') return 'Neplatný kód pobočky.';
        if (err == 'unauthorized') return 'Neplatný kiosk token pro tuto pobočku.';
        return null; // párování funguje
      }
      return 'Neočekávaná odpověď serveru.';
    } catch (e) {
      return 'Chyba spojení se serverem.';
    }
  }
}
