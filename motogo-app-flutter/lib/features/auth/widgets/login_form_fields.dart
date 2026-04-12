import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Email input field for the login screen.
class LoginEmailField extends StatelessWidget {
  const LoginEmailField({
    super.key,
    required this.controller,
  });

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          style: const TextStyle(fontSize: 15, color: MotoGoColors.black),
          decoration: InputDecoration(
            hintText: 'vas@email.com',
            hintStyle: TextStyle(color: MotoGoColors.g400.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MotoGoColors.g200, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MotoGoColors.g200, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MotoGoColors.green, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Password input field for the login screen.
class LoginPasswordField extends StatelessWidget {
  const LoginPasswordField({
    super.key,
    required this.controller,
    required this.obscureText,
    required this.onToggleObscure,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(context).tr('passwordLabel'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: MotoGoColors.g400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          autofillHints: const [AutofillHints.password],
          style: const TextStyle(fontSize: 15, color: MotoGoColors.black),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: TextStyle(color: MotoGoColors.g400.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: MotoGoColors.g400,
                size: 20,
              ),
              onPressed: onToggleObscure,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MotoGoColors.g200, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MotoGoColors.g200, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MotoGoColors.green, width: 2),
            ),
          ),
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}
