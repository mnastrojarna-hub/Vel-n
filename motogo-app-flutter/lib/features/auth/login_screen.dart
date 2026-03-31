import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import 'auth_provider.dart';
import 'biometric_service.dart';
import 'widgets/toast_helper.dart';

/// Login screen — 1:1 mirror of s-login from auth-ui.js.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _bioAvailable = false;
  bool _bioEnabled = false;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
    _checkBiometric();
  }

  Future<void> _prefillEmail() async {
    final email = await AuthService.getSavedEmail();
    if (email != null && _emailCtrl.text.isEmpty) {
      _emailCtrl.text = email;
    }
  }

  Future<void> _checkBiometric() async {
    final available = await BiometricService.isAvailable();
    final enabled = await AuthService.isBioEnabled();
    final hasBioUser = await AuthService.getBioUser() != null;
    if (mounted) {
      setState(() {
        _bioAvailable = available && hasBioUser;
        _bioEnabled = enabled;
      });
    }
  }

  Future<void> _doLogin() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      showMotoGoToast(context, icon: '✗', title: 'Chyba', message: 'Vyplňte email a heslo');
      return;
    }

    setState(() => _loading = true);
    final error = await AuthService.signIn(email, pass);
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showMotoGoToast(context, icon: '✗', title: 'Chyba přihlášení', message: error);
    } else {
      showMotoGoToast(context, icon: '✓', title: 'Přihlášení', message: 'Vítejte zpět!');
      context.go(Routes.home);
    }
  }

  Future<void> _doBioLogin() async {
    final ok = await BiometricService.authenticate();
    if (!ok) {
      if (mounted) showMotoGoToast(context, icon: 'ℹ️', title: 'Biometrika', message: 'Ověření zrušeno');
      return;
    }

    if (mounted) showMotoGoToast(context, icon: '🔐', title: 'Biometrika', message: 'Ověřeno – přihlašuji...');

    final sessionOk = await AuthService.bioRestoreSession();
    if (!mounted) return;

    if (sessionOk) {
      context.go(Routes.home);
    } else {
      await AuthService.clearBioData();
      showMotoGoToast(context, icon: 'ℹ️', title: 'Biometrika', message: 'Session vypršela – přihlašte se emailem');
      setState(() {
        _bioAvailable = false;
        _bioEnabled = false;
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              // Logo area
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: MotoGoColors.green,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text('🏍️', style: TextStyle(fontSize: 32)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MOTO GO 24',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: MotoGoColors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Text(
                      'PŮJČOVNA MOTOREK',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: MotoGoColors.g400,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Login card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  boxShadow: [
                    BoxShadow(
                      color: MotoGoColors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Přihlášení',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: MotoGoColors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Heslo'),
                      onSubmitted: (_) => _doLogin(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loading ? null : _doLogin,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('PŘIHLÁSIT SE'),
                    ),
                    const SizedBox(height: 12),
                    // Biometric login button
                    if (_bioAvailable && _bioEnabled)
                      OutlinedButton.icon(
                        onPressed: _doBioLogin,
                        icon: const Text('🔐', style: TextStyle(fontSize: 18)),
                        label: const Text('Biometrické přihlášení'),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        // TODO: Forgot password dialog (Part 2)
                      },
                      child: const Text(
                        'Zapomenuté heslo?',
                        style: TextStyle(
                          color: MotoGoColors.g400,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Register link
              Center(
                child: TextButton(
                  onPressed: () => context.push(Routes.register),
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 13, color: MotoGoColors.g400),
                      children: [
                        TextSpan(text: 'Nemáte účet? '),
                        TextSpan(
                          text: 'Zaregistrujte se',
                          style: TextStyle(
                            color: MotoGoColors.greenDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
