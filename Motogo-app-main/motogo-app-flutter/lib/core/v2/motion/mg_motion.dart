import 'package:flutter/widgets.dart';

/// v2 motion tokens (PLAN §1.3, v1 spec §2.7). Every v2 animation checks
/// [reduced] and snaps to its END state when the system asks for reduced
/// motion. Loops are wrapped in `RepaintBoundary` and pause via `TickerMode`.
abstract final class MgMotion {
  static const press = Duration(milliseconds: 150);
  static const color = Duration(milliseconds: 180);
  static const tab = Duration(milliseconds: 210);
  static const fabState = Duration(milliseconds: 150);
  static const pop = Duration(milliseconds: 300);
  static const sheet = Duration(milliseconds: 300);
  static const sticky = Duration(milliseconds: 300);
  static const thumb = Duration(milliseconds: 300);
  static const hero = Duration(milliseconds: 350);
  static const enter = Duration(milliseconds: 450);
  static const reveal = Duration(milliseconds: 550);
  static const revealStagger = Duration(milliseconds: 70);
  static const bump = Duration(milliseconds: 450);
  static const shake = Duration(milliseconds: 300);
  static const scanOnce = Duration(milliseconds: 600);
  static const connector = Duration(milliseconds: 700);
  static const marks = Duration(milliseconds: 700);
  static const pathCard = Duration(milliseconds: 900);
  static const pathDetail = Duration(milliseconds: 1600);
  static const toast = Duration(milliseconds: 2800);
  static const toastAction = Duration(milliseconds: 4000);
  static const kenBurns = Duration(seconds: 8);

  // Loops (one primary CTA fx + one live indicator per screen, max).
  static const glowLoop = Duration(milliseconds: 2200);
  static const sheenLoop = Duration(milliseconds: 4800);
  static const glintLoop = Duration(milliseconds: 3600);
  static const edgeLoop = Duration(milliseconds: 4000);
  static const emberLoop = Duration(milliseconds: 4400);
  static const pingLoop = Duration(milliseconds: 1800);
  static const shimmerLoop = Duration(milliseconds: 1200);
  static const pendingLoop = Duration(milliseconds: 1200);

  /// Road-tier shine: 3.2 s at step 1 → 2.6 s at step 5.
  static Duration shineLoop(int step) =>
      Duration(milliseconds: (3200 - 150 * (step - 1).clamp(0, 4)).round());

  // Curves.
  static const ease = Curves.ease;
  static const emphasized = Cubic(0.2, 0, 0, 1);
  static const spring = Cubic(0.3, 1.35, 0.5, 1);
  static const out = Curves.easeOutCubic;

  /// true = the platform asks for reduced motion → snap to end states.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when motion is reduced.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

  static final Set<String> _played = <String>{};

  /// true the FIRST time [key] is asked in this app session (one-shot
  /// ambients, first-build reveals).
  static bool firstTime(String key) => _played.add(key);

  /// Forgets the one-shot flags (tests).
  @visibleForTesting
  static void resetSession() => _played.clear();
}
