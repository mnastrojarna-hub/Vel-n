import 'package:flutter/services.dart';

/// v2 haptics (design G8, V2 §1.3 / §4.3): [select] for press, selection,
/// committed swipe / snap / month; [sos] ONLY for the SOS entry pill. The
/// old toast helper keeps its own light impact. Nothing else vibrates.
abstract final class MgHaptic {
  static void select() => HapticFeedback.selectionClick();

  static void sos() => HapticFeedback.heavyImpact();
}
