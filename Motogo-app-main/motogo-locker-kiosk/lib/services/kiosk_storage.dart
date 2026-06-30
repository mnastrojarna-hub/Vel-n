import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Identita tabletu (zařízení) — unikátní device_id + device_token z Velína.
/// Nastaví se jednou při prvním spuštění (Setup); tablet je pak natrvalo
/// přiřazený k jednomu zařízení/pobočce.
class KioskStorage {
  KioskStorage._();
  static final KioskStorage instance = KioskStorage._();

  static const _kDeviceId = 'mg_kiosk_device_id';
  static const _kDeviceToken = 'mg_kiosk_device_token';
  static const _kBranchName = 'mg_kiosk_branch_name';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? deviceId;
  String? deviceToken;
  String? branchName;

  bool get isConfigured =>
      (deviceId?.isNotEmpty ?? false) && (deviceToken?.isNotEmpty ?? false);

  Future<void> load() async {
    deviceId = await _storage.read(key: _kDeviceId);
    deviceToken = await _storage.read(key: _kDeviceToken);
    branchName = await _storage.read(key: _kBranchName);
  }

  Future<void> save({
    required String deviceId,
    required String deviceToken,
    String? branchName,
  }) async {
    this.deviceId = deviceId.trim();
    this.deviceToken = deviceToken.trim();
    if (branchName != null) this.branchName = branchName.trim();
    await _storage.write(key: _kDeviceId, value: this.deviceId);
    await _storage.write(key: _kDeviceToken, value: this.deviceToken);
    if (this.branchName != null) {
      await _storage.write(key: _kBranchName, value: this.branchName);
    }
  }

  Future<void> setBranchName(String name) async {
    branchName = name;
    await _storage.write(key: _kBranchName, value: name);
  }

  Future<void> clear() async {
    deviceId = null;
    deviceToken = null;
    branchName = null;
    await _storage.delete(key: _kDeviceId);
    await _storage.delete(key: _kDeviceToken);
    await _storage.delete(key: _kBranchName);
  }
}
