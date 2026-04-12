import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Primary "PŘIHLÁSIT SE" login button.
class LoginSubmitButton extends StatelessWidget {
  const LoginSubmitButton({
    super.key,
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MotoGoColors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.login, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    t(context).loginBtn,
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

/// Biometric login button (only shown when biometrics available & enabled).
class LoginBiometricButton extends StatelessWidget {
  const LoginBiometricButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.fingerprint, size: 22),
        label: Text(
          t(context).tr('biometric'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: MotoGoColors.greenDark,
          side: const BorderSide(color: MotoGoColors.green, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
        ),
      ),
    );
  }
}

/// "Zapomněli jste heslo?" forgot password text button.
class LoginForgotPasswordButton extends StatelessWidget {
  const LoginForgotPasswordButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.lock_reset, size: 16, color: MotoGoColors.greenDark),
        label: Text(
          t(context).tr('forgotPasswordBtn'),
          style: const TextStyle(
            color: MotoGoColors.greenDark,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// "nebo" divider row between login and register actions.
class LoginOrDivider extends StatelessWidget {
  const LoginOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: MotoGoColors.g200, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t(context).tr('or'),
            style: TextStyle(
              fontSize: 13,
              color: MotoGoColors.g400,
            ),
          ),
        ),
        Expanded(child: Divider(color: MotoGoColors.g200, thickness: 1)),
      ],
    );
  }
}

/// "REGISTROVAT SE" register button.
class LoginRegisterButton extends StatelessWidget {
  const LoginRegisterButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: MotoGoColors.black,
          side: const BorderSide(color: MotoGoColors.g200, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add_alt_1, size: 18),
            const SizedBox(width: 8),
            Text(
              t(context).registerBtn,
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
