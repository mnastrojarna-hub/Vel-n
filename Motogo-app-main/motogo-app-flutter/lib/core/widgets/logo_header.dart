import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';

/// Runtime app version — initialized once at startup from pubspec.yaml values.
/// Falls back to '?.?.?' until init() is called.
String appVersion = 'v?.?.?';

/// Must be called once from main() before runApp.
Future<void> initAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  appVersion = 'v${info.version}+${info.buildNumber}';
}

/// Shared MotoGo24 logo row — used in headers across all main screens.
/// Matches the hdr-top section from Capacitor templates-screens.js.
class LogoRow extends StatelessWidget {
  final bool compact;
  const LogoRow({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final double logoSize = compact ? 48 : 64;
    final double logoRadius = compact ? 12 : 14;
    final double iconSize = compact ? 26 : 36;
    final double titleSize = compact ? 22 : 26;
    final double subtitleSize = compact ? 11 : 14;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(logoRadius),
          child: Image.asset(
            'assets/logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: logoSize,
              height: logoSize,
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(logoRadius),
              ),
              child: Icon(Icons.motorcycle, size: iconSize, color: Colors.black),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MOTO GO 24',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'PŮJČOVNA MOTOREK',
                style: TextStyle(
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                  letterSpacing: 2.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

