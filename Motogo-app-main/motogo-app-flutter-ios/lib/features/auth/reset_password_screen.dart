import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import 'auth_provider.dart';
import 'widgets/toast_helper.dart';

/// 3-step password reset flow — mirrors auth-session.js showForgotPassword().
/// Step 1: Enter email → sends OTP code
/// Step 2: Enter 8-digit code from email
/// Step 3: Set new password
class ResetPasswordScreen extends StatefulWidget {
  /// Optional pre-filled email from login screen.
  final String? initialEmail;

  const ResetPasswordScreen({super.key, this.initialEmail});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  int _step = 1;
  bool _loading = false;
  String _email = '';

  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pass1Ctrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  bool _obscurePass1 = true;
  bool _obscurePass2 = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailCtrl.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _pass1Ctrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  /// Back button — go to previous step or pop screen.
  void _onBack() {
    if (_step > 1) {
      setState(() => _step--);
    } else {
      context.go(Routes.login);
    }
  }

  /// Step 1: Send OTP code to email.
  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showMotoGoToast(context,
          icon: '⚠️', title: t(context).email, message: t(context).tr('validEmailMsg'));
      return;
    }

    setState(() => _loading = true);
    final error = await AuthService.resetPassword(email);
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showMotoGoToast(context, icon: '✗', title: t(context).error, message: error);
      return;
    }

    _email = email;
    showMotoGoToast(context,
        icon: '📧', title: t(context).tr('codeSent'), message: t(context).tr('checkEmail'));
    setState(() => _step = 2);
  }

  /// Step 2: Verify OTP code.
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 8) {
      showMotoGoToast(context,
          icon: '⚠️', title: t(context).tr('codeLabel'), message: t(context).tr('enter8DigitCode'));
      return;
    }

    setState(() => _loading = true);
    final error = await AuthService.verifyOtp(_email, code);
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showMotoGoToast(context, icon: '✗', title: t(context).error, message: error);
      return;
    }

    showMotoGoToast(context,
        icon: '✓', title: t(context).tr('codeCorrect'), message: t(context).tr('enterNewPassword'));
    setState(() => _step = 3);
  }

  /// Step 3: Set new password.
  Future<void> _setPassword() async {
    final p1 = _pass1Ctrl.text;
    final p2 = _pass2Ctrl.text;

    if (p1.length < 8) {
      showMotoGoToast(context,
          icon: '⚠️', title: t(context).password, message: t(context).tr('passwordMinLengthMsg'));
      return;
    }
    if (p1 != p2) {
      showMotoGoToast(context,
          icon: '⚠️', title: t(context).password, message: t(context).tr('passwordsNoMatch'));
      return;
    }

    setState(() => _loading = true);
    final error = await AuthService.updatePassword(p1);
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showMotoGoToast(context, icon: '✗', title: t(context).error, message: error);
      return;
    }

    // Sign out recovery session — user logs in with new password
    await AuthService.signOut();
    if (!mounted) return;

    showMotoGoToast(context,
        icon: '✓',
        title: t(context).tr('passwordChanged'),
        message: t(context).tr('loginWithNewPassword'));
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Dark header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 12,
              16,
              20,
            ),
            decoration: const BoxDecoration(
              gradient: MotoGoGradients.loginHeader,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button
                GestureDetector(
                  onTap: _onBack,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: MotoGoDimens.backBtnSize,
                        height: MotoGoDimens.backBtnSize,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                              MotoGoDimens.backBtnRadius),
                        ),
                        alignment: Alignment.center,
                        child: const Text('←',
                            style: TextStyle(
                                fontSize: 18, color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        t(context).tr('backToLogin'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t(context).tr('resetPasswordTitle'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Content
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
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Step indicator
                      _buildStepIndicator(),
                      const SizedBox(height: 24),

                      // Step content
                      if (_step == 1) _buildStep1(),
                      if (_step == 2) _buildStep2(),
                      if (_step == 3) _buildStep3(),
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

  Widget _buildStepIndicator() {
    return Row(
      children: [
        for (int i = 1; i <= 3; i++) ...[
          if (i > 1) const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= _step
                    ? MotoGoColors.green
                    : MotoGoColors.g200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(context).tr('enterEmail'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MotoGoColors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t(context).tr('resetEmailDesc'),
          style: TextStyle(fontSize: 14, color: MotoGoColors.g400),
        ),
        const SizedBox(height: 20),
        Text(
          t(context).tr('emailLabel'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: MotoGoColors.g400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          style: const TextStyle(fontSize: 15, color: MotoGoColors.black),
          decoration: _inputDecoration('vas@email.com'),
          onSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 24),
        _buildButton(
          label: t(context).tr('sendCode'),
          icon: Icons.mail_outline,
          onPressed: _sendCode,
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(context).tr('enterCode'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MotoGoColors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${t(context).tr('enterCodeDesc')} $_email',
          style: TextStyle(fontSize: 14, color: MotoGoColors.g400),
        ),
        const SizedBox(height: 20),
        Text(
          t(context).tr('codeLabel'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: MotoGoColors.g400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 8,
          style: const TextStyle(
            fontSize: 24,
            color: MotoGoColors.black,
            letterSpacing: 6,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _inputDecoration('12345678').copyWith(
            counterText: '',
          ),
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 16),
        // Resend code button
        Center(
          child: TextButton(
            onPressed: _loading ? null : _sendCode,
            child: Text(
              t(context).tr('resendCode'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MotoGoColors.greenDark,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildButton(
          label: t(context).tr('verifyCodeBtn'),
          icon: Icons.check_circle_outline,
          onPressed: _verifyCode,
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(context).tr('newPassword'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MotoGoColors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t(context).tr('newPasswordDesc'),
          style: TextStyle(fontSize: 14, color: MotoGoColors.g400),
        ),
        const SizedBox(height: 20),
        Text(
          t(context).tr('newPasswordLabel'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: MotoGoColors.g400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pass1Ctrl,
          obscureText: _obscurePass1,
          style: const TextStyle(fontSize: 15, color: MotoGoColors.black),
          decoration: _inputDecoration('••••••••').copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePass1
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: MotoGoColors.g400,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePass1 = !_obscurePass1),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          t(context).tr('passwordAgain'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: MotoGoColors.g400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pass2Ctrl,
          obscureText: _obscurePass2,
          style: const TextStyle(fontSize: 15, color: MotoGoColors.black),
          decoration: _inputDecoration('••••••••').copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePass2
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: MotoGoColors.g400,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePass2 = !_obscurePass2),
            ),
          ),
          onSubmitted: (_) => _setPassword(),
        ),
        const SizedBox(height: 24),
        _buildButton(
          label: t(context).tr('setPassword'),
          icon: Icons.lock_outline,
          onPressed: _setPassword,
        ),
      ],
    );
  }

  /// Shared input decoration matching login screen style.
  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: MotoGoColors.g400.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: MotoGoColors.g200, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: MotoGoColors.g200, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: MotoGoColors.green, width: 2),
      ),
    );
  }

  /// Shared green pill button matching login screen style.
  Widget _buildButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MotoGoColors.green,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          elevation: 0,
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
