import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import 'auth_provider.dart';
import 'biometric_service.dart';
import 'widgets/toast_helper.dart';
import 'widgets/login_header.dart';
import 'widgets/login_form_fields.dart';
import 'widgets/login_buttons.dart';
import 'widgets/login_footer.dart';

/// Login screen — 1:1 replica of the Capacitor MotoGo24 login UI.
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
  bool _obscurePass = true;

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
      showMotoGoToast(context, icon: '✗', title: t(context).error, message: t(context).tr('fillEmailAndPassword'));
      return;
    }

    setState(() => _loading = true);
    final error = await AuthService.signIn(email, pass);
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showMotoGoToast(context, icon: '✗', title: t(context).tr('loginError'), message: error);
    } else {
      showMotoGoToast(context, icon: '✓', title: t(context).login, message: t(context).welcome);
      context.go(Routes.home);
    }
  }

  Future<void> _doBioLogin() async {
    final ok = await BiometricService.authenticate();
    if (!ok) {
      if (mounted) showMotoGoToast(context, icon: 'ℹ️', title: t(context).tr('biometricTitle'), message: t(context).tr('authCancelled'));
      return;
    }

    if (mounted) showMotoGoToast(context, icon: '🔐', title: t(context).tr('biometricTitle'), message: t(context).tr('bioVerified'));

    final sessionOk = await AuthService.bioRestoreSession();
    if (!mounted) return;

    if (sessionOk) {
      context.go(Routes.home);
    } else {
      await AuthService.clearBioData();
      showMotoGoToast(context, icon: 'ℹ️', title: t(context).tr('biometricTitle'), message: t(context).tr('sessionExpired'));
      setState(() {
        _bioAvailable = false;
        _bioEnabled = false;
      });
    }
  }

  void _forgotPassword() {
    final email = _emailCtrl.text.trim();
    final uri = Uri(
      path: Routes.resetPassword,
      queryParameters: email.isNotEmpty ? {'email': email} : null,
    );
    context.push(uri.toString());
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
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Dark gradient header with logo
          const LoginHeader(),

          // White content area
          Expanded(
            child: SingleChildScrollView(
              child: Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(MotoGoRadius.login),
                      topRight: Radius.circular(MotoGoRadius.login),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      Text(
                        t(context).tr('loginTitle'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: MotoGoColors.black,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t(context).tr('loginSubtitle'),
                        style: TextStyle(
                          fontSize: 14,
                          color: MotoGoColors.g400,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // E-MAIL field
                      LoginEmailField(controller: _emailCtrl),
                      const SizedBox(height: 18),

                      // HESLO field
                      LoginPasswordField(
                        controller: _passCtrl,
                        obscureText: _obscurePass,
                        onToggleObscure: () => setState(() => _obscurePass = !_obscurePass),
                        onSubmitted: _doLogin,
                      ),
                      const SizedBox(height: 24),

                      // PŘIHLÁSIT SE button
                      LoginSubmitButton(
                        loading: _loading,
                        onPressed: _doLogin,
                      ),

                      // Biometric login button
                      if (_bioAvailable && _bioEnabled) ...[
                        const SizedBox(height: 12),
                        LoginBiometricButton(onPressed: _doBioLogin),
                      ],

                      const SizedBox(height: 14),

                      // Zapomněli jste heslo?
                      LoginForgotPasswordButton(onPressed: _forgotPassword),

                      const SizedBox(height: 8),

                      // "nebo" divider
                      const LoginOrDivider(),

                      const SizedBox(height: 16),

                      // REGISTROVAT SE button
                      LoginRegisterButton(
                        onPressed: () => context.push(Routes.register),
                      ),

                      const SizedBox(height: 24),

                      // Footer: phone + website + version
                      const LoginFooter(),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
