import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';

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

/// Sdílený dialog pro úpravu přezdívky pilota — používá ho domovská hlavička
/// i hlavička profilu (duplicitní vstup dle požadavku zákazníka). Přezdívka je
/// jen lokální (SharedPreferences), nemění skutečné `full_name` v profilu.
void showNicknameDialog(
  BuildContext context,
  WidgetRef ref, {
  String? fullName,
}) {
  final current = ref.read(nicknameProvider) ?? extractFirstName(fullName);
  final firstName = extractFirstName(fullName);
  final controller = TextEditingController(text: current);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        t(context).tr('editNickname'),
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        cursorColor: Colors.black,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          hintText: firstName,
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3)),
          enabledBorder: UnderlineInputBorder(
            borderSide:
                BorderSide(color: MotoGoColors.green.withValues(alpha: 0.4)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: MotoGoColors.green),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(nicknameProvider.notifier).clearNickname();
            Navigator.of(ctx).pop();
          },
          child: Text('Reset',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.5))),
        ),
        TextButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) {
              ref.read(nicknameProvider.notifier).setNickname(value);
            }
            Navigator.of(ctx).pop();
          },
          child: const Text('OK',
              style: TextStyle(
                  color: MotoGoColors.green, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}
