import 'package:flutter/material.dart';
import '../theme.dart';

/// Shared MotoGo24 logo row — used in headers across all main screens.
/// Matches the hdr-top section from Capacitor templates-screens.js.
class LogoRow extends StatelessWidget {
  final bool compact;
  const LogoRow({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 8 : 10),
          child: Image.asset(
            'assets/logo.png',
            width: compact ? 28 : 36,
            height: compact ? 28 : 36,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: compact ? 28 : 36,
              height: compact ? 28 : 36,
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(compact ? 8 : 10),
              ),
              child: Icon(Icons.motorcycle, size: compact ? 16 : 20, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MOTO GO 24',
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'PŮJČOVNA MOTOREK',
              style: TextStyle(
                fontSize: compact ? 7 : 9,
                fontWeight: FontWeight.w700,
                color: Colors.white38,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// App version constant — displayed in login footer + profile.
const String appVersion = 'v1.7.2';
