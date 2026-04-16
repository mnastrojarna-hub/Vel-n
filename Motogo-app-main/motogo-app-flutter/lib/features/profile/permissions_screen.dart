import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/native/permission_service.dart';
import '../auth/auth_provider.dart';
import '../auth/biometric_service.dart';
import '../auth/widgets/toast_helper.dart';

/// Full-screen permissions management — replaces old bottom sheet.
/// Shows current status of each permission with tap to open system settings.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
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
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('←',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.black)),
              ),
            ),
          ),
        ),
        title: const Text('Oprávnění aplikace',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        backgroundColor: MotoGoColors.dark,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Oprávnění udělená při prvním spuštění.\n'
              'Klikněte na oprávnění pro změnu v nastavení telefonu.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: MotoGoColors.g400),
            ),
            const SizedBox(height: 16),
            if (_perms == null)
              const Padding(
                padding: EdgeInsets.all(20),
                child:
                    Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
              )
            else
              ..._perms!.map((p) => _permRow(p)),
            if (_bioAvailable) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: MotoGoColors.g200),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Biometrické přihlášení',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: MotoGoColors.black)),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  if (!_bioEnabled) {
                    final ok = await BiometricService.authenticate();
                    if (ok) {
                      showMotoGoToast(context,
                          icon: '✓',
                          title: 'Biometrika',
                          message: 'Aktivována');
                    }
                  } else {
                    await AuthService.clearBioData();
                    showMotoGoToast(context,
                        icon: 'ℹ️',
                        title: 'Biometrika',
                        message: 'Deaktivována');
                  }
                  await _loadBio();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _bioEnabled
                        ? MotoGoColors.greenPale
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _bioEnabled
                            ? MotoGoColors.g200
                            : const Color(0xFFFECACA)),
                  ),
                  child: Row(children: [
                    const Text('🔐', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Otisk prstu / Face ID',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: MotoGoColors.black)),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _bioEnabled
                            ? MotoGoColors.green
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _bioEnabled
                                ? MotoGoColors.green
                                : MotoGoColors.g300,
                            width: 2),
                      ),
                      child: _bioEnabled
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.black)
                          : null,
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
                label: const Text('Otevřít nastavení telefonu',
                    style: TextStyle(fontWeight: FontWeight.w800)),
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
                        title: 'Oprávnění',
                        message: 'Oprávnění znovu vyžádána');
                  }
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: const Text('Povolit vše znovu',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permRow(PermissionInfo p) {
    return GestureDetector(
      onTap: () async {
        await PermissionService.openSettings();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.granted ? MotoGoColors.greenPale : const Color(0xFFFEF2F2),
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
                Text(p.title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: MotoGoColors.black)),
                Text(p.desc,
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
              p.granted ? 'Povoleno' : 'Zakázáno',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: p.granted ? Colors.black : Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 18, color: MotoGoColors.g400),
        ]),
      ),
    );
  }
}
