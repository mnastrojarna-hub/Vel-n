import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Uložení párování kiosku s pobočkou (branch_code + kiosk_token) v secure storage.
/// Nastaví se jednou při prvním spuštění (Setup), tablet je pak natrvalo
/// přiřazený k jedné pobočce.
class KioskStorage {
  KioskStorage._();
  static final KioskStorage instance = KioskStorage._();

  static const _kBranchCode = 'mg_kiosk_branch_code';
  static const _kBranchName = 'mg_kiosk_branch_name';
  static const _kToken = 'mg_kiosk_token';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? branchCode;
  String? branchName;
  String? token;

  bool get isConfigured =>
      (branchCode?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);

  Future<void> load() async {
    branchCode = await _storage.read(key: _kBranchCode);
    branchName = await _storage.read(key: _kBranchName);
    token = await _storage.read(key: _kToken);
  }

  Future<void> save({
    required String branchCode,
    required String token,
    String? branchName,
  }) async {
    this.branchCode = branchCode.trim();
    this.token = token.trim();
    this.branchName = branchName?.trim();
    await _storage.write(key: _kBranchCode, value: this.branchCode);
    await _storage.write(key: _kToken, value: this.token);
    if (this.branchName != null) {
      await _storage.write(key: _kBranchName, value: this.branchName);
    }
  }

  Future<void> clear() async {
    branchCode = null;
    branchName = null;
    token = null;
    await _storage.delete(key: _kBranchCode);
    await _storage.delete(key: _kBranchName);
    await _storage.delete(key: _kToken);
  }
}
