import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../currency.dart';
import '../theme.dart';
import '../i18n/i18n_provider.dart';
import '../native/permission_service.dart';
import '../widgets/mg_back.dart';
import '../widgets/state_views.dart' show MgBackArrow;

/// Language selection overlay — shown on first app launch.
/// Mirrors lang-overlay from index.html + lang-select.js.
/// Checks mg_locale in SharedPreferences (same as mg_lang in localStorage).
/// Zvolený jazyk se hned POUŽIJE (localeProvider → UI, rezervace, e-maily,
/// smlouvy) — dřív se jen uložil do `mg_locale`, který appka nečetla.
class LanguageOverlay extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                          onTap: () => _selectLang(_langs[i1].$1, ref),
                        )),
                        const SizedBox(width: 10),
                        if (i2 < _langs.length)
                          Expanded(child: _LangBtn(
                            flag: _langs[i2].$2,
                            name: _langs[i2].$3,
                            onTap: () => _selectLang(_langs[i2].$1, ref),
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

  Future<void> _selectLang(String code, WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mg_locale', code);
    await ref.read(localeProvider.notifier).setLocale(Locale(code));
    // Měna podle jazyka (CZK/EUR/PLN) — jen když si ji zákazník ručně nezvolil.
    // Bez await: stahování kurzů ČNB (timeout 8 s) nesmí držet uvítací
    // obrazovku — měna se přepne hned, kurzy dorazí na pozadí.
    unawaited(ref.read(currencyProvider.notifier).followLanguage(code));
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
class PermissionOverlay extends StatefulWidget {
  final VoidCallback onAllow;
  final VoidCallback onSkip;
  /// Zpět na výběr jazyka (šipka i systémové zpět — požadavek majitele:
  /// z každé obrazovky jde zpět; dřív „zpět" appku zavřel).
  final VoidCallback? onBack;
  const PermissionOverlay(
      {super.key, required this.onAllow, required this.onSkip, this.onBack});

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
  State<PermissionOverlay> createState() => _PermissionOverlayState();
}

class _PermissionOverlayState extends State<PermissionOverlay> {
  // Blokuje druhý tap během běžícího nativního requestu — souběžný request
  // permission_handler odmítá PlatformException a shodil by appku.
  bool _requesting = false;

  Future<void> _onAllowTap() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await PermissionOverlay.requestAllPermissions();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
    if (!mounted) return;
    widget.onAllow();
  }

  void _back() {
    if (!_requesting) widget.onBack?.call();
  }

  @override
  Widget build(BuildContext context) {
    final onBack = widget.onBack;
    return MgOverlayBack(
      // Běží systémový dialog oprávnění → zpět patří jemu (nic nepřepínat).
      onBack: () {
        if (onBack == null) return false;
        _back();
        return true;
      },
      child: Material(
      color: MotoGoColors.black.withValues(alpha: 0.97),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: onBack == null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: MgBackArrow(onTap: _back),
                      ),
              ),
              Text(t(context).tr('welcomeToMotoGo'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Text(t(context).tr('needConsentForFull'),
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 24),
              ...PermissionOverlay._perms.map((p) => _PermItem(icon: p.$1, title: p.$2, desc: p.$3)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _requesting ? null : _onAllowTap,
                  child: Text(t(context).tr('allowAllContinue')),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _requesting ? null : widget.onSkip,
                child: Text(t(context).tr('skipSetupLater'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
              ),
            ],
          ),
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
