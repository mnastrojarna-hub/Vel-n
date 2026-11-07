import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';

/// First-run coach of the AI button (V2 §4.2 "First run"): one bubble
/// "Zeptej se kdykoli. Jsme tu pro tebe.", dismissed on tap, never repeated
/// (shared_preferences [prefKey]).
abstract final class MgAiCoach {
  static const prefKey = 'mg_v2_ai_coach_seen';
  static bool? _seen;

  /// Whether the bubble was already dismissed (cached for the process).
  static Future<bool> seen() async {
    if (_seen != null) return _seen!;
    try {
      final p = await SharedPreferences.getInstance();
      _seen = p.getBool(prefKey) ?? false;
    } catch (_) {
      _seen = true; // no storage → never nag
    }
    return _seen!;
  }

  static Future<void> markSeen() async {
    _seen = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefKey, true);
    } catch (_) {}
  }

  /// Forgets the cached value (tests: a new "app start").
  @visibleForTesting
  static void debugReset() => _seen = null;
}

/// The coach bubble: night glass r14 left of the disc, text 12.5/700, ✕ 44.
class MgAiCoachBubble extends StatelessWidget {
  final VoidCallback onClose;
  const MgAiCoachBubble({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgEnter(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: MgColors.night.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MgColors.neonA(0.25)),
            boxShadow: [BoxShadow(color: MgColors.black(0.28), blurRadius: 18, spreadRadius: -6, offset: const Offset(0, 8))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(tr.tr('v2UxCoreAiCoach'),
                      style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark)),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: tr.tr('close'),
              excludeSemantics: true,
              onTap: onClose,
              child: MgPress(
                scale: 0.92,
                onTap: onClose,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(child: MgIcon(MgIcons.close, size: 16, color: MgColors.onDarkSecondary)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
