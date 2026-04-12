import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Dark gradient header widget for the login screen (logo + tagline).
class LoginHeader extends StatelessWidget {
  const LoginHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 18,
        24,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: MotoGoGradients.loginHeader,
      ),
      child: Column(
        children: [
          // Logo + MOTO GO 24 on one row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/logo.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: MotoGoColors.green,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.motorcycle, size: 26, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'MOTO GO 24',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t(context).tr('tagline'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: MotoGoColors.green,
            ),
          ),
        ],
      ),
    );
  }
}
