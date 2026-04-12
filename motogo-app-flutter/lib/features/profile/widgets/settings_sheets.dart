import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../auth/auth_provider.dart';
import '../../auth/biometric_service.dart';
import '../../auth/widgets/toast_helper.dart';
import 'package:go_router/go_router.dart';

/// Shows a bottom sheet for changing password.
void showChangePasswordSheet(BuildContext context) {
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Změna hesla',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
        const SizedBox(height: 16),
        TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nové heslo (min. 8 znaků)')),
        const SizedBox(height: 10),
        TextField(
            controller: confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Potvrďte heslo')),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () async {
            if (passCtrl.text.length < 8) {
              showMotoGoToast(context, icon: '⚠️', title: 'Heslo', message: 'Min. 8 znaků');
              return;
            }
            if (passCtrl.text != confirmCtrl.text) {
              showMotoGoToast(context, icon: '⚠️', title: 'Heslo', message: 'Hesla se neshodují');
              return;
            }
            final err = await AuthService.updatePassword(passCtrl.text);
            if (ctx.mounted) Navigator.pop(ctx);
            if (err != null) {
              showMotoGoToast(context, icon: '✗', title: 'Chyba', message: err);
            } else {
              showMotoGoToast(context, icon: '✓', title: 'Hotovo', message: 'Heslo změněno');
            }
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_reset, size: 18),
            SizedBox(width: 8),
            Text('Změnit heslo'),
          ]),
        ),
      ]),
    ),
  );
}

/// Shows a bottom sheet for toggling biometric login.
Future<void> showBiometricToggleSheet(BuildContext context) async {
  final available = await BiometricService.isAvailable();
  if (!available) {
    if (context.mounted) {
      showMotoGoToast(context, icon: 'ℹ️', title: 'Biometrika', message: 'Zařízení nepodporuje biometriku');
    }
    return;
  }
  final enabled = await AuthService.isBioEnabled();
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Biometrické přihlášení',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              if (!enabled) {
                final ok = await BiometricService.authenticate();
                if (ok) {
                  showMotoGoToast(context, icon: '✓', title: 'Biometrika', message: 'Aktivována');
                }
              } else {
                await AuthService.clearBioData();
                showMotoGoToast(context, icon: 'ℹ️', title: 'Biometrika', message: 'Deaktivována');
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Expanded(
                  child: Text('Otisk prstu / Face ID',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: enabled ? MotoGoColors.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: enabled ? MotoGoColors.green : MotoGoColors.g300, width: 2),
                  ),
                  child: enabled ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                ),
              ]),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Shows a bottom sheet for selecting the app language.
void showLanguagePickerSheet(BuildContext context, WidgetRef ref) {
  final langs = [
    ('cs', 'Čeština 🇨🇿'),
    ('en', 'English 🇬🇧'),
    ('de', 'Deutsch 🇩🇪'),
    ('es', 'Español 🇪🇸'),
    ('fr', 'Français 🇫🇷'),
    ('nl', 'Nederlands 🇳🇱'),
    ('pl', 'Polski 🇵🇱'),
  ];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Jazyk aplikace',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 16),
          ...langs.map((l) => ListTile(
            title: Text(l.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            trailing: ref.read(localeProvider).languageCode == l.$1
                ? const Icon(Icons.check, color: MotoGoColors.greenDark)
                : null,
            onTap: () async {
              await ref.read(localeProvider.notifier).setLocale(Locale(l.$1));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                showMotoGoToast(context, icon: '🌐', title: 'Jazyk změněn', message: l.$2);
                // Force full app rebuild by navigating to home
                context.go(Routes.home);
              }
            },
          )),
        ]),
      ),
    ),
  );
}
