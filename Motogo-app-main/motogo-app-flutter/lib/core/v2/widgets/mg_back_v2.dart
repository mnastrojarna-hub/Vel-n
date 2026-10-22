import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/i18n_provider.dart';
import '../../widgets/mg_nav_controls.dart' show MgBackTap;
import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';

/// Surface the back / close disc sits on (DESIGN_V22 §6.1).
enum MgBackStyle {
  /// Over a photo or map: night .80 + 1 px white .25 ring + shadow.
  photo,

  /// Dark header / dark sheet: white .10 + 1 px white .25.
  dark,

  /// Light screen / light sheet: white + 1 px line + icon shadow.
  light,
}

/// The v2 back / close control: 44 px disc (hit 48 via `MgBackTap`),
/// chevron ‹ (back one step) or ✕ (leave a modal / viewer / result). Callers
/// pass the SAME onTap the old screen used (`context.backOr(...)`, `_onBack`,
/// `Navigator.pop`) — system back stays owned by the existing guards.
/// Semantics "Zpět" / "Zavřít" (+ tooltip on long-press).
class MgV2Back extends StatefulWidget {
  final VoidCallback? onTap;
  final bool close;
  final MgBackStyle style;

  /// Custom screen-reader label (e.g. "Ukončit jízdu").
  final String? label;
  final double size;

  const MgV2Back({
    super.key,
    required this.onTap,
    this.close = false,
    this.style = MgBackStyle.dark,
    this.label,
    this.size = 44,
  });

  @override
  State<MgV2Back> createState() => _MgV2BackState();
}

class _MgV2BackState extends State<MgV2Back> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final label = widget.label ?? (widget.close ? tr.tr('close') : tr.back);
    final (fill, ring, fg, shadow) = switch (widget.style) {
      MgBackStyle.photo => (MgColors.nightA(0.80), MgColors.white(0.25), MgColors.onDark, MgShadows.photoControl),
      MgBackStyle.dark => (MgColors.white(0.10), MgColors.white(0.25), MgColors.onDark, null),
      MgBackStyle.light => (MgColors.surface, MgColors.line, MgColors.ink, MgShadows.icon),
    };
    final pressedFill = widget.style == MgBackStyle.light
        ? Color.alphaBlend(MgColors.inkA(0.08), fill)
        : Color.alphaBlend(MgColors.white(0.08), fill);
    final reduced = MgMotion.reduced(context);
    final disc = AnimatedScale(
      scale: _down && !reduced ? 0.92 : 1,
      duration: MgMotion.press,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _down ? pressedFill : fill,
          shape: BoxShape.circle,
          border: Border.all(color: ring),
          boxShadow: shadow,
        ),
        child: Center(
          child: MgIcon(
            widget.close ? MgIcons.close : MgIcons.chevronLeft,
            size: 24,
            color: fg,
          ),
        ),
      ),
    );
    // MgBackTap (hit slop 48) MUST stay outermost — every wrapper between it
    // and the parent would only test its own 44 px bounds.
    return MgBackTap(
      close: widget.close,
      label: label,
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.longPress,
        child: Listener(
          onPointerDown: (_) => setState(() => _down = true),
          onPointerUp: (_) => setState(() => _down = false),
          onPointerCancel: (_) => setState(() => _down = false),
          child: disc,
        ),
      ),
    );
  }
}
