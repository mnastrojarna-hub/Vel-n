import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_guard.dart' show ForcedSignOut;
import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import 'auth_error_mapper.dart';
import 'auth_provider.dart';
import 'biometric_service.dart';
import 'widgets/toast_helper.dart';
import 'widgets/login_header.dart';
import 'widgets/login_form_fields.dart';
import 'widgets/login_buttons.dart';
import 'widgets/login_footer.dart';

/// Login screen — 1:1 replica of the Capacitor MotoGo24 login UI.
class LoginScreen extends ConsumerStatefulWidget {
  /// E-mail z registrace („účet už existuje → Přihlásit“) — zákazník ho
  /// nepíše znovu (`/login?email=…`, stejně jako obnova hesla).
  final String? initialEmail;
  const LoginScreen({super.key, this.initialEmail});

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
  // Zapamatovaný e-mail posledního přihlášení (do registrace se nenese —
  // ten účet už existuje).
  String? _savedEmail;

  @override
  void initState() {
    super.initState();
    _carryEmail(widget.initialEmail);
    _prefillEmail();
    _checkBiometric();
    // Appka zákazníka odhlásila sama (neplatné / zneplatněné přihlášení) →
    // jednou vysvětlit proč a že se nic neztratilo.
    if (ForcedSignOut.pending) {
      ForcedSignOut.pending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showMotoGoToast(context,
            icon: '🔒',
            title: t(context).tr('eoAuthTitle'),
            message: t(context).tr('eoForcedSignOut'),
            duration: const Duration(seconds: 8));
      });
    }
  }

  @override
  void didUpdateWidget(LoginScreen old) {
    super.didUpdateWidget(old);
    // Návrat z registrace na už otevřené přihlášení (`go` stránku znovu použije).
    if (widget.initialEmail != old.initialEmail) _carryEmail(widget.initialEmail);
  }

  void _carryEmail(String? email) {
    final e = email?.trim() ?? '';
    if (e.isNotEmpty) _emailCtrl.text = e;
  }

  Future<void> _prefillEmail() async {
    final email = await AuthService.getSavedEmail();
    _savedEmail = email;
    if (email != null && _emailCtrl.text.isEmpty) {
      _emailCtrl.text = email;
    }
  }

  /// Registrace s e-mailem, který zákazník už napsal (ne zapamatovaný
  /// e-mail existujícího účtu; [unknown] = ověřeně bez účtu) — nepíše ho
  /// podruhé.
  void _openRegister({bool unknown = false}) {
    final e = _emailCtrl.text.trim();
    final carry = e.isNotEmpty && (unknown || e != _savedEmail?.trim());
    context.push(carry
        ? Uri(path: Routes.register, queryParameters: {'email': e}).toString()
        : Routes.register);
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
    final AuthErrorInfo? error = await AuthService.signIn(email, pass);
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
        showMotoGoToast(context,
            icon: '✗',
            title: error.title,
            message: error.message,
            duration: const Duration(seconds: 7));
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
              _openRegister(unknown: true);
            },
            child: Text(t(context).registerBtn,
                style: const TextStyle(color: MotoGoColors.greenDark, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _doBioLogin() async {
    final bio = await BiometricService.authenticateResult();
    if (bio != BioAuthResult.ok) {
      if (!mounted) return;
      // Zablokovaná / nenastavená biometrie ≠ „zrušeno" — řekni proč a co dál.
      final msg = switch (bio) {
        BioAuthResult.lockedOut => t(context).tr('eoBioLocked'),
        BioAuthResult.notEnrolled => t(context).tr('eoBioNotEnrolled'),
        BioAuthResult.unavailable => t(context).tr('eoBioUnavailable'),
        _ => t(context).tr('authCancelled'),
      };
      showMotoGoToast(context,
          icon: 'ℹ️',
          title: t(context).tr('biometricTitle'),
          message: msg,
          duration: Duration(seconds: bio == BioAuthResult.cancelled ? 3 : 7));
      return;
    }

    if (mounted) showMotoGoToast(context, icon: '🔐', title: t(context).tr('biometricTitle'), message: t(context).tr('bioVerified'));

    final restore = await AuthService.bioRestoreSession();
    if (!mounted) return;

    if (restore == BioRestore.ok) {
      context.go(Routes.home);
    } else if (restore == BioRestore.offline) {
      // Bez signálu nemazat nastavení biometrie — stačí to zkusit znovu.
      showMotoGoToast(context,
          icon: '📡',
          title: t(context).tr('eoOfflineTitle'),
          message: t(context).tr('eoBioOffline'),
          duration: const Duration(seconds: 7));
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
                        onPressed: () => _openRegister(),
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
