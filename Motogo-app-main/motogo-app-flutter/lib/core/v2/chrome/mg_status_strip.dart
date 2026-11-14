import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_word_fit.dart';

/// What a status strip is about (icon disc colour; meaning, never rank).
enum MgStripKind { sos, pay, verifying, docs, route, cart }

/// T4 global strip (night glass r14, icon disc 36 / icon 20, title 14/800 +
/// optional sub, chevron, ✕ 44 only when today's FAB has one). The v2 face
/// of the shell FABs: same visibility rules, same onTap / onDismiss
/// closures (they stay in `shell_fabs.dart`).
class MgStatusStrip extends StatelessWidget {
  final MgStripKind kind;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final String? dismissLabel;

  /// The dismiss DESTROYS something (pay strip: cancel the unfinished
  /// booking) — drawn as a small red "Zrušit" pill, never the neutral ✕
  /// that means "hide" on the other strips (AFT-01). Same [onDismiss].
  final bool dismissDestructive;

  /// Further active strips (v1 C2, V2 §4.4: ONE strip + "+n"): a chip left
  /// of the chevron; [onMore] opens the rest (null = the strip's own tap).
  final int more;
  final VoidCallback? onMore;

  const MgStatusStrip({
    super.key,
    required this.kind,
    required this.title,
    required this.onTap,
    this.sub,
    this.onDismiss,
    this.dismissLabel,
    this.dismissDestructive = false,
    this.more = 0,
    this.onMore,
  });

  Widget _moreChip(BuildContext context) {
    final label = t(context).tr('v2UxCoreMore').replaceAll('{n}', '$more');
    final chip = Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: MgColors.neonA(0.16), borderRadius: BorderRadius.circular(16)),
      child: Center(
        widthFactor: 1,
        child: Text('+$more',
            maxLines: 1,
            softWrap: false,
            style: MgType.tab(MgType.small.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: MgColors.neonText))),
      ),
    );
    return Semantics(
      button: onMore != null,
      label: label,
      excludeSemantics: true,
      onTap: onMore,
      child: onMore == null
          ? chip
          : MgPress(scale: 0.92, onTap: onMore, child: SizedBox(height: 44, child: Center(child: chip))),
    );
  }

  static final _titleStyle = MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.25);
  static final _subStyle = MgType.tab(MgType.small.copyWith(height: 1.25));
  static final _cancelStyle = MgType.small.copyWith(fontSize: 12, fontWeight: FontWeight.w800);

  /// RD-01: true when, with the worded "Zrušit" pill, the title / subtitle
  /// column would be narrower than [kMgStripMinText] or its longest word.
  bool _compactCancel(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler.scale(1) > 1.15) return true;
    // The app font comes from the theme / DefaultTextStyle, as for the Text.
    final base = DefaultTextStyle.of(context).style;
    double w(String s, TextStyle st) {
      final p = TextPainter(
          text: TextSpan(text: s, style: base.merge(st)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
        ..layout();
      final r = p.width;
      p.dispose();
      return r;
    }

    double word(String s, TextStyle st) => s.split(RegExp(r'[ \n]')).fold(0.0, (m, x) => math.max(m, w(x, st)));
    // Pill: border 3 + padding 20 + icon 16 + gap 4 + word + margin 6.
    final pill = math.max(44.0, 49 + w(t(context).tr('coStripCancel'), _cancelStyle));
    // Main row: padding 12 + disc 36 + gap 12 + chevron 20 (+ "+N" chip).
    final column = width - pill - 80 - (more > 0 ? 52 : 0);
    final sub = this.sub;
    final need = math.max(kMgStripMinText, math.max(word(title, _titleStyle), sub == null ? 0.0 : word(sub, _subStyle)));
    return column < need;
  }

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String icon, Gradient? g) = switch (kind) {
      MgStripKind.sos => (MgColors.sos, MgColors.onDark, MgIcons.alert, null),
      MgStripKind.pay => (MgColors.neon, MgColors.onNeon, MgIcons.card, MgGradients.neon),
      MgStripKind.verifying => (MgColors.warnDark, MgColors.onNeon, MgIcons.clock, null),
      MgStripKind.docs => (MgColors.warnBorder, const Color(0xFF3A2400), MgIcons.docs, null),
      MgStripKind.route => (const Color(0x00000000), MgColors.neon, MgIcons.navigate, null),
      MgStripKind.cart => (MgColors.white(0.10), MgColors.onDark, MgIcons.cart, null),
    };
    final disc = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: g == null ? bg : null,
        gradient: g,
        shape: BoxShape.circle,
        border: kind == MgStripKind.route ? Border.all(color: MgColors.neon, width: 1.5) : null,
      ),
      child: Center(child: MgIcon(icon, size: 20, color: fg)),
    );
    final lines = kind == MgStripKind.sos ? 3 : 2;
    final main = Semantics(
      button: true,
      label: sub == null ? title : '$title, $sub',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(children: [
              disc,
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Nikdy „…" uprostřed výzvy (SOS!): text se nejdřív zmenší,
                  // pak smí na 2 řádky (SOS na 3) a pruh se zvýší.
                  MgWordFit(
                    minScale: 0.85,
                    child: Text(title,
                        maxLines: lines,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.25, color: MgColors.onDark)),
                  ),
                  if (sub != null)
                    MgWordFit(
                      minScale: 0.85,
                      child: Text(sub!,
                          maxLines: lines,
                          overflow: TextOverflow.ellipsis,
                          style: MgType.tab(MgType.small.copyWith(height: 1.25, color: MgColors.onDarkSecondary))),
                    ),
                ]),
              ),
              if (more > 0) ...[_moreChip(context), const SizedBox(width: 6)],
              const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.neonText),
            ]),
          ),
        ),
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        // Solid like MgDock (r2): a 95 % fill without a backdrop blur let the
        // page text underneath ghost through the strip.
        color: MgColors.night,
        borderRadius: BorderRadius.circular(14),
        // P2-04: the unpaid-booking strip is THE thing to do — full neon
        // edge; the other strips keep the quiet one.
        border: kind == MgStripKind.pay
            ? Border.all(color: MgColors.neon, width: 2)
            : Border.all(color: MgColors.neonA(0.3)),
        boxShadow: [BoxShadow(color: MgColors.black(0.28), blurRadius: 18, spreadRadius: -6, offset: const Offset(0, 8))],
      ),
      // RD-01: when the pill's word would squeeze the title / amount (narrow
      // phone, long language) or the text is large, the destructive pill
      // drops its word (icon only, same border, tap target, label, action).
      child: LayoutBuilder(builder: (context, box) {
        final compact = dismissDestructive && _compactCancel(context, box.maxWidth);
        return Row(children: [
          Expanded(child: main),
          if (onDismiss != null)
            Semantics(
              button: true,
              label: dismissLabel ?? t(context).tr('close'),
              excludeSemantics: true,
              onTap: onDismiss,
              child: MgPress(
                scale: 0.92,
                onTap: onDismiss,
                child: dismissDestructive
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        child: Center(
                          widthFactor: 1,
                          child: Container(
                            key: ValueKey(compact ? 'mg-strip-cancel-icon' : 'mg-strip-cancel-text'),
                            height: 32,
                            constraints: const BoxConstraints(minWidth: 32),
                            margin: const EdgeInsetsDirectional.only(end: 6),
                            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
                            // P2-04: outlined, so it no longer outweighs the
                            // pay action next to it (still red = destroys).
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: MgColors.errDark, width: 1.5),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const MgIcon(MgIcons.trash, size: 16, color: MgColors.errDark),
                                  if (!compact) ...[
                                    const SizedBox(width: 4),
                                    Text(t(context).tr('coStripCancel'),
                                        maxLines: 1,
                                        softWrap: false,
                                        style: MgType.small.copyWith(
                                            fontSize: 12, fontWeight: FontWeight.w800, color: MgColors.errDark)),
                                  ],
                                ]),
                          ),
                        ),
                      )
                    : SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(color: MgColors.white(0.10), shape: BoxShape.circle),
                            child: const Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.onDark)),
                          ),
                        ),
                      ),
              ),
            ),
        ]);
      }),
    );
  }
}

/// RD-01: the title / amount column keeps at least this width beside a
/// worded destructive pill; below it the pill shows only its icon.
const double kMgStripMinText = 120;
