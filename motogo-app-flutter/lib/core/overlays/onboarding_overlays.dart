import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

/// Language selection overlay — shown on first app launch.
/// Mirrors lang-overlay from index.html + lang-select.js.
/// Checks mg_locale in SharedPreferences (same as mg_lang in localStorage).
class LanguageOverlay extends StatelessWidget {
  final VoidCallback onDone;
  const LanguageOverlay({super.key, required this.onDone});

  static const _langs = [
    ('cs', '🇨🇿', 'Čeština'),
    ('en', '🇬🇧', 'English'),
    ('de', '🇩🇪', 'Deutsch'),
    ('pl', '🇵🇱', 'Polski'),
    ('fr', '🇫🇷', 'Français'),
    ('es', '🇪🇸', 'Español'),
    ('nl', '🇳🇱', 'Nederlands'),
  ];

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mg_locale') == null;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MotoGoColors.black.withValues(alpha: 0.97),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏍️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text('MotoGo24',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                const SizedBox(height: 6),
                Text('Choose your language / Vyberte jazyk',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
                const SizedBox(height: 28),
                // 2-column grid to match original lang-grid
                ...List.generate((_langs.length / 2).ceil(), (row) {
                  final i1 = row * 2;
                  final i2 = i1 + 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: _LangBtn(
                          flag: _langs[i1].$2,
                          name: _langs[i1].$3,
                          onTap: () => _selectLang(_langs[i1].$1, context),
                        )),
                        const SizedBox(width: 10),
                        if (i2 < _langs.length)
                          Expanded(child: _LangBtn(
                            flag: _langs[i2].$2,
                            name: _langs[i2].$3,
                            onTap: () => _selectLang(_langs[i2].$1, context),
                          ))
                        else
                          const Expanded(child: SizedBox()),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectLang(String code, BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mg_locale', code);
    onDone();
  }
}

class _LangBtn extends StatelessWidget {
  final String flag, name;
  final VoidCallback onTap;
  const _LangBtn({required this.flag, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
          ],
        ),
      ),
    );
  }
}

/// Permission request overlay — shown after language selection.
/// Mirrors perm-overlay from index.html + grantPerms() from native-bridge.js.
/// Actually requests native permissions when user taps "Povolit vše".
class PermissionOverlay extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onSkip;
  const PermissionOverlay({super.key, required this.onAllow, required this.onSkip});

  static const _perms = [
    ('🔐', 'Biometrické ověření', 'Rychlé přihlášení pomocí otisku prstu'),
    ('📍', 'Poloha', 'Navigace k půjčovně, sdílení pozice při poruše'),
    ('📷', 'Fotoaparát', 'Skenování dokladů, dokumentace škod'),
    ('🎤', 'Mikrofon', 'Hlasové dotazy pro AI asistenta'),
    ('🔔', 'Oznámení', 'SOS aktualizace, zprávy z MotoGo24, stav rezervací'),
  ];

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('mg_perms_shown') != true;
  }

  /// Request all native permissions — mirrors grantPerms() from Capacitor.
  static Future<void> requestAllPermissions() async {
    try {
      // GPS
      await Geolocator.requestPermission();
    } catch (_) {}
    try {
      // Push notifications (Firebase)
      await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
        announcement: true, provisional: false,
      );
    } catch (_) {}
    // Camera + Microphone are requested at point-of-use (image_picker, etc.)
    // Biometric is handled by local_auth at point-of-use
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MotoGoColors.black.withValues(alpha: 0.97),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text('🏍️ Vítejte v MotoGo24',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Text('Pro plnou funkčnost potřebujeme váš souhlas',
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 24),
              ..._perms.map((p) => _PermItem(icon: p.$1, title: p.$2, desc: p.$3)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    await requestAllPermissions();
                    onAllow();
                  },
                  child: const Text('Povolit vše a pokračovat →'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSkip,
                child: Text('Přeskočit – nastavím později',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermItem extends StatelessWidget {
  final String icon, title, desc;
  const _PermItem({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(desc, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
            ],
          )),
        ],
      ),
    );
  }
}
