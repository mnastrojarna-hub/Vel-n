import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/currency.dart';
import '../../../core/native/permission_service.dart';
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
        Text(t(context).tr('changePassword'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
        const SizedBox(height: 16),
        TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: InputDecoration(labelText: t(context).tr('newPasswordHint'))),
        const SizedBox(height: 10),
        TextField(
            controller: confirmCtrl,
            obscureText: true,
            decoration: InputDecoration(labelText: t(context).tr('confirmPasswordLabel'))),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () async {
            if (passCtrl.text.length < 8) {
              showMotoGoToast(context, icon: '⚠️', title: t(context).tr('password'), message: t(context).tr('min8chars'));
              return;
            }
            if (passCtrl.text != confirmCtrl.text) {
              showMotoGoToast(context, icon: '⚠️', title: t(context).tr('password'), message: t(context).tr('passwordsDoNotMatch'));
              return;
            }
            final err = await AuthService.updatePassword(passCtrl.text);
            if (ctx.mounted) Navigator.pop(ctx);
            // Po awaitu ověř, že vnější obrazovka je stále v tree — jinak by
            // toast na neplatném contextu spadl (parita s lang/currency sheety).
            if (!context.mounted) return;
            if (err != null) {
              showMotoGoToast(context, icon: '✗', title: t(context).tr('error'), message: err);
            } else {
              showMotoGoToast(context, icon: '✓', title: t(context).tr('success'), message: t(context).tr('passwordChanged'));
            }
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock_reset, size: 18),
            const SizedBox(width: 8),
            Text(t(context).tr('changePasswordBtn')),
          ]),
        ),
      ]),
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
    ('uk', 'Українська 🇺🇦'),
  ];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t(context).tr('language'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
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
                showMotoGoToast(context, icon: '🌐', title: t(context).tr('languageChanged'), message: l.$2);
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

/// Bottom sheet pro volbu měny (CZK/EUR/PLN) — parita s webem: ceny se jen
/// ZOBRAZUJÍ v přepočtu dle kurzu ČNB, platby kartou probíhají vždy v CZK.
void showCurrencyPickerSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t(context).tr('currency'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 6),
          Text(t(context).tr('currencyNote'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
          const SizedBox(height: 12),
          ...supportedCurrencies.map((c) => ListTile(
            title: Text('${c.flag} ${c.code} — ${c.symbol}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: c.code == 'CZK'
                ? null
                : Text('1 ${c.code} ≈ ${(Money.rates[c.code] ?? 0).toStringAsFixed(2)} Kč (ČNB)',
                    style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
            trailing: ref.read(currencyProvider) == c.code
                ? const Icon(Icons.check, color: MotoGoColors.greenDark)
                : null,
            onTap: () async {
              await ref.read(currencyProvider.notifier).setCurrency(c.code);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                showMotoGoToast(context, icon: '💱',
                    title: t(context).tr('currencyChanged'),
                    message: '${c.flag} ${c.code}');
                // Force full app rebuild by navigating to home (jako u jazyka)
                context.go(Routes.home);
              }
            },
          )),
        ]),
      ),
    ),
  );
}

/// Shows a bottom sheet for managing app permissions.
/// Displays current status of each permission and allows opening system settings.
void showPermissionsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _PermissionsSheet(),
  );
}

class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet();

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet>
    with WidgetsBindingObserver {
  List<PermissionInfo>? _perms;
  bool _bioAvailable = false;
  bool _bioEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadBio();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Reload statuses when user returns from system settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final statuses = await PermissionService.getStatuses();
    if (mounted) setState(() => _perms = statuses);
  }

  Future<void> _loadBio() async {
    final available = await BiometricService.isAvailable();
    final enabled = available ? await AuthService.isBioEnabled() : false;
    if (mounted) setState(() { _bioAvailable = available; _bioEnabled = enabled; });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t(context).tr('permissions'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: MotoGoColors.black)),
          const SizedBox(height: 6),
          Text(
            '${t(context).tr('permsGrantedFirstRun')}\n'
            '${t(context).tr('permsRevokeHint')}',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                color: MotoGoColors.g400),
          ),
          const SizedBox(height: 16),
          if (_perms == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: MotoGoColors.green),
            )
          else
            ..._perms!.map((p) => _permRow(p)),
          if (_bioAvailable) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: MotoGoColors.g200),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(t(context).tr('biometric'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                if (!_bioEnabled) {
                  final ok = await BiometricService.authenticate();
                  if (ok) {
                    // Ulož povolení + bio-uživatele (jinak se zapnutí neuloží
                    // a přepínač spadne zpět na OFF).
                    final saved = await AuthService.enableBiometric();
                    if (!mounted) return;
                    showMotoGoToast(context, icon: saved ? '✓' : 'ℹ️', title: t(context).tr('biometricsTitle'), message: t(context).tr(saved ? 'activated' : 'sessionExpired'));
                  }
                } else {
                  await AuthService.clearBioData();
                  if (!mounted) return;
                  showMotoGoToast(context, icon: 'ℹ️', title: t(context).tr('biometricsTitle'), message: t(context).tr('deactivated'));
                }
                await _loadBio();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _bioEnabled ? MotoGoColors.greenPale : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _bioEnabled ? MotoGoColors.g200 : const Color(0xFFFECACA)),
                ),
                child: Row(children: [
                  const Text('🔐', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(t(context).tr('fingerprintFaceId'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                  ),
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: _bioEnabled ? MotoGoColors.green : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _bioEnabled ? MotoGoColors.green : MotoGoColors.g300, width: 2),
                    ),
                    child: _bioEnabled ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await PermissionService.openSettings();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: MotoGoColors.green,
                foregroundColor: MotoGoColors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
              ),
              icon: const Icon(Icons.settings, size: 18),
              label: Text(t(context).tr('openPhoneSettings'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await PermissionService.requestAll();
                await _load();
                if (context.mounted) {
                  showMotoGoToast(context,
                      icon: '✅',
                      title: t(context).tr('permissionLabel'),
                      message: t(context).tr('permsRerequested'));
                }
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
              ),
              child: Text(t(context).tr('allowAllAgain'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _permRow(PermissionInfo p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.granted
            ? MotoGoColors.greenPale
            : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: p.granted ? MotoGoColors.g200 : const Color(0xFFFECACA)),
      ),
      child: Row(children: [
        Text(p.icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t(context).tr(p.title),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: MotoGoColors.black)),
              Text(t(context).tr(p.desc),
                  style: const TextStyle(
                      fontSize: 10, color: MotoGoColors.g400)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: p.granted ? MotoGoColors.green : MotoGoColors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            p.granted ? t(context).tr('allowedLabel') : t(context).tr('deniedLabel'),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: p.granted ? Colors.black : Colors.white),
          ),
        ),
      ]),
    );
  }
}
