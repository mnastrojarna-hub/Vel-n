import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

/// Offline cache aktivních kódů + mapování dveří.
/// Tablet periodicky stahuje přes kiosk_sync_codes; při výpadku internetu
/// se kód ověří lokálně (a dveře otevřou — relé je na LAN, funguje bez internetu).
class CodeCache {
  CodeCache._();
  static final CodeCache instance = CodeCache._();

  static const _key = 'mg_kiosk_codes_cache';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Map<String, dynamic>? _data;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) _data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
  }

  /// Stáhne čerstvá data z backendu a uloží.
  Future<void> sync() async {
    final res = await KioskApi.instance.syncCodes();
    if (res == null) return;
    _data = Map<String, dynamic>.from(res);
    try {
      await _storage.write(key: _key, value: jsonEncode(_data));
    } catch (_) {}
  }

  List<DoorInfo> get _doors =>
      ((_data?['doors'] as List?) ?? const []).whereType<Map>().map((d) => DoorInfo.fromMap(d)).toList();

  ResolveResult _wrap({
    required String kind,
    DoorInfo? door,
    List<DoorInfo> doors = const [],
    String? bookingId,
    int? boxNumber,
  }) {
    final d = _data ?? const {};
    return ResolveResult(
      ok: true,
      kind: kind,
      door: door,
      doors: doors,
      bookingId: bookingId,
      boxNumber: boxNumber,
      musicOnUrl: d['music_on_url'] as String?,
      musicOffUrl: d['music_off_url'] as String?,
      musicSeconds: (d['music_seconds'] as int?) ?? 90,
      doorOpenSeconds: (d['door_open_seconds'] as int?) ?? 8,
      lightSeconds: (d['light_seconds'] as int?) ?? 120,
      doorConfigured: door != null && (door.relayUrl ?? '').isNotEmpty,
    );
  }

  /// Lokální ověření kódu (offline). Vrací null = neznámý/neplatný.
  ResolveResult? resolveLocal(String code) {
    if (_data == null) return null;
    final c = code.trim();
    if (c.isEmpty) return null;

    // Servisní heslo → seznam všech dveří
    final services = ((_data!['service_codes'] as List?) ?? const []).map((e) => '$e').toList();
    if (services.contains(c)) {
      return _wrap(kind: 'service', doors: _doors);
    }

    // Zákaznický kód
    final codes = ((_data!['codes'] as List?) ?? const []).whereType<Map>();
    for (final row in codes) {
      if ('${row['code']}' != c) continue;
      // kontrola platnosti
      final vu = row['valid_until'];
      if (vu is String) {
        final until = DateTime.tryParse(vu);
        if (until != null && until.isBefore(DateTime.now())) continue;
      }
      final door = DoorInfo(
        id: row['door_id'] as String?,
        kind: row['kind'] as String?,
        boxNumber: row['box_number'] as int?,
        label: row['label'] as String?,
        relayUrl: row['relay_url'] as String?,
        lightUrl: row['light_url'] as String?,
      );
      return _wrap(
        kind: (row['kind'] as String?) ?? 'motorcycle',
        door: door.id == null && (door.relayUrl ?? '').isEmpty ? null : door,
        bookingId: row['booking_id'] as String?,
        boxNumber: row['box_number'] as int?,
      );
    }
    return null;
  }
}
