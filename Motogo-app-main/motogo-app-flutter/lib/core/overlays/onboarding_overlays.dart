import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../i18n/i18n_provider.dart';
import '../native/permission_service.dart';

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
    ('uk', '🇺🇦', 'Українська'),
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

  // (icon, titleKey, descKey) — texts resolved via t(context).tr in _PermItem.
  static const _perms = [
    ('📍', 'permLocationTitle', 'permLocationDesc'),
    ('📷', 'permCameraTitle', 'permCameraDesc'),
    ('🎤', 'permMicTitle', 'permMicDesc'),
    ('🔔', 'permNotifTitle', 'permNotifDesc'),
    ('🖼️', 'permPhotosTitle', 'permPhotosDesc'),
    ('🔐', 'obBiometricTitle', 'obBiometricDesc'),
  ];

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('mg_perms_shown') != true;
  }

  /// Request ALL native permissions at once — GPS, camera, microphone,
  /// notifications, gallery. Sets them in system settings so point-of-use
  /// code never re-asks. Biometric is handled by local_auth separately.
  static Future<void> requestAllPermissions() async {
    await PermissionService.requestAll();
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
              Text(t(context).tr('welcomeToMotoGo'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Text(t(context).tr('needConsentForFull'),
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
                  child: Text(t(context).tr('allowAllContinue')),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSkip,
                child: Text(t(context).tr('skipSetupLater'),
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
              Text(t(context).tr(title), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(t(context).tr(desc), style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
            ],
          )),
        ],
      ),
    );
  }
}
