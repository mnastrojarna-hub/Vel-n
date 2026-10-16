import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// One chat line as the AI screen's State built it (no own logic).
class AiChatItemV2 {
  final String text;
  final bool isBot;
  final bool isSosHint;
  final bool isError;
  final bool failed;
  final List<Uint8List> images;
  final VoidCallback? onRetry;
  const AiChatItemV2({
    required this.text,
    required this.isBot,
    this.isSosHint = false,
    this.isError = false,
    this.failed = false,
    this.images = const [],
    this.onRetry,
  });
}

/// Strips a leading status emoji the logic texts carry (❌ / ⏳) — the v2
/// look shows a line icon instead.
String aiStripLead(String s) => s.replaceFirst(RegExp(r'^(❌|⏳)\s*'), '');

/// Chat bubble on the dark chat (board `.ai-m`): bot = glass, me = neon,
/// error = red tint + ✕ icon, failed own message = "Zkusit znovu".
class AiBubbleV2 extends StatelessWidget {
  final AiChatItemV2 item;
  final bool sending;
  const AiBubbleV2({super.key, required this.item, required this.sending});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final m = item;
    final me = !m.isBot;
    final err = m.isError;
    final bg = err ? MgColors.sos.withValues(alpha: 0.16) : (me ? null : MgColors.white(0.07));
    final border = err ? MgColors.errDark.withValues(alpha: 0.45) : (me ? null : MgColors.neonA(0.18));
    final fg = me ? MgColors.onNeon : MgColors.onDarkBody;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (err ? 0.92 : 0.86)),
        child: MgEnter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              gradient: me ? const LinearGradient(colors: [MgColors.neonHi, MgColors.neonLo]) : null,
              border: border == null ? null : Border.all(color: border),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(me ? 16 : 6),
                bottomRight: Radius.circular(me ? 6 : 16),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (m.images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final img in m.images)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(img, width: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 80)),
                      ),
                  ]),
                ),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (err) ...[
                  const MgIcon(MgIcons.xCircle, size: 20, color: MgColors.errDark),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(err ? aiStripLead(m.text) : m.text,
                      style: MgType.small.copyWith(fontSize: 13.5, height: 1.45, color: fg)),
                ),
              ]),
              if (m.failed && m.onRetry != null) ...[
                const SizedBox(height: 6),
                Semantics(
                  button: true,
                  child: MgPress(
                    onTap: sending ? null : m.onRetry,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        MgIcon(MgIcons.refresh, size: 16, color: fg),
                        const SizedBox(width: 4),
                        Text(tr.tr('eoRetry'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
                      ]),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// SOS card in the chat (red system, never rank) → /sos.
class AiSosCardV2 extends StatelessWidget {
  final VoidCallback onTap;
  const AiSosCardV2({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MgColors.errBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MgColors.errBorder),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: MgColors.sos, shape: BoxShape.circle),
              child: const Center(child: MgIcon(MgIcons.sos, size: 20, color: MgColors.onDark)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('reportSosIncident'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.err)),
                Text(tr.tr('v2TapToReport'), style: MgType.small.copyWith(color: MgColors.err)),
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.err),
          ]),
        ),
      ),
    );
  }
}

/// "Přemýšlím…" with three bouncing dots — the chat's one live indicator
/// (static under reduced motion).
class AiTypingV2 extends StatefulWidget {
  final String label;
  const AiTypingV2({super.key, required this.label});

  @override
  State<AiTypingV2> createState() => _AiTypingV2State();
}

class _AiTypingV2State extends State<AiTypingV2> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MgMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MgMotion.reduced(context);
    Widget dot(int i) => AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final p = reduced ? 0.0 : ((_c.value * 2 - i * 0.3) % 2).clamp(0.0, 1.0);
            final up = p < 0.5 ? p * 2 : (1 - p) * 2;
            return Transform.translate(
              offset: Offset(0, -3 * up),
              child: Opacity(
                opacity: 0.5 + 0.5 * up,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: MgColors.neonText, shape: BoxShape.circle),
                ),
              ),
            );
          },
        );
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        liveRegion: true,
        label: widget.label,
        excludeSemantics: true,
        child: RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: MgColors.white(0.07), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              dot(0),
              const SizedBox(width: 4),
              dot(1),
              const SizedBox(width: 4),
              dot(2),
              const SizedBox(width: 10),
              Flexible(
                child: Text(aiStripLead(widget.label),
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkMeta)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
