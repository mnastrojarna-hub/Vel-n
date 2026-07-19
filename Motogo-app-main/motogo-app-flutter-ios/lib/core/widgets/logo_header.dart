import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';
import 'moto_fx.dart';
import '../../features/loyalty/loyalty_provider.dart';
import '../../features/loyalty/loyalty_ranks_screen.dart';

/// Runtime app version — initialized once at startup from pubspec.yaml values.
/// Falls back to '?.?.?' until init() is called.
String appVersion = 'v?.?.?';

/// Must be called once from main() before runApp.
Future<void> initAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  appVersion = 'v${info.version}';
}

/// Shared MotoGo24 logo row — used in headers across all main screens.
/// Matches the hdr-top section from Capacitor templates-screens.js.
///
/// Věrnostní ranky: logo samotné zůstává VŽDY 1:1 originál (nikdy se
/// nepřebarvuje) — barva aktuálního ranku se zobrazuje jako široký barevný
/// ring + záře OKOLO loga. Bez ranku (nepřihlášen / backend bez loyalty)
/// vypadá hlavička přesně jako dřív.
class LogoRow extends ConsumerWidget {
  final bool compact;
  const LogoRow({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double logoSize = compact ? 48 : 64;
    final double logoRadius = compact ? 12 : 14;
    final double iconSize = compact ? 26 : 36;
    final double titleSize = compact ? 22 : 26;
    // O maličko menší podtitulek + užší prostrkání, aby se vešlo celé
    // „PŮJČOVNA MOTOREK" a neořezávalo se na „MOTORE…".
    final double subtitleSize = compact ? 10 : 12.5;
    // Široký barevný proužek kolem loga dle ranku.
    final double ringWidth = compact ? 4 : 5;

    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;

    Widget logo = ClipRRect(
      borderRadius: BorderRadius.circular(logoRadius),
      child: Image.asset(
        'assets/logo.webp',
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
    );

    if (loyalty != null) {
      final ringColor = loyalty.color;
      final glowColor =
          loyalty.isLegend ? const Color(0xFFFF8C00) : ringColor;
      logo = Container(
        padding: EdgeInsets.all(ringWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(logoRadius + ringWidth),
          color: loyalty.isLegend ? null : ringColor,
          gradient: loyalty.isLegend
              ? const LinearGradient(
                  colors: legendGradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.55),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: logo,
      );
      // „Ikona ranku" je klikatelná — otevře animovaný přehled všech ranků.
      logo = PressableScale(
        pressedScale: 0.9,
        onTap: () => openLoyaltyRanks(context),
        child: logo,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
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
                  letterSpacing: 1.2,
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

