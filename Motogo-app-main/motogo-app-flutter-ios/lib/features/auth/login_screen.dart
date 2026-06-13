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

    if (error != null) {
      // Supabase nerozlišuje „neznámý e-mail" od „špatné heslo". Doptáme se
      // RPC: když e-mail neexistuje, nasměrujeme zákazníka na registraci
      // (místo matoucího „přihlášení selhalo").
      final known = await AuthService.emailExists(email);
      if (!mounted) return;
      setState(() => _loading = false);
      if (known == false) {
        _showUnknownEmailDialog();
      } else {
        showMotoGoToast(context, icon: '✗', title: t(context).tr('loginError'), message: error);
      }
    } else {
      setState(() => _loading = false);
      showMotoGoToast(context, icon: '✓', title: t(context).login, message: t(context).welcome);
      context.go(Routes.home);
    }
  }

  /// Neznámý e-mail při přihlášení → nabídni vytvoření registrace.
  void _showUnknownEmailDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(context).tr('loginUnknownEmailTitle'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(t(context).tr('loginUnknownEmailBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t(context).cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push(Routes.register);
            },
            child: Text(t(context).registerBtn,
                style: const TextStyle(color: MotoGoColors.greenDark, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
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
                      const SizedBox(height: 14),

                      // Nápověda pro zákazníky z webu — stejný účet funguje v appce.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: MotoGoColors.greenPale,
                          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                          border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Text('🌐', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t(context).tr('loginWebAccountHint'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: MotoGoColors.greenDarker,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

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
