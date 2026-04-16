import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _nicknameKey = 'mg_pilot_nickname';

/// Provides the locally stored pilot nickname.
/// Defaults to null (= use first name from profile).
final nicknameProvider =
    StateNotifierProvider<NicknameNotifier, String?>((ref) {
  return NicknameNotifier();
});

class NicknameNotifier extends StateNotifier<String?> {
  NicknameNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_nicknameKey);
  }

  Future<void> setNickname(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameKey, trimmed);
    state = trimmed;
  }

  Future<void> clearNickname() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nicknameKey);
    state = null;
  }
}

/// Extracts the first name (first word) from full_name.
String extractFirstName(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) return 'Pilot';
  return fullName.trim().split(' ').first;
}
