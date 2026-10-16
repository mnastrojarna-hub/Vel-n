import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_word_fit.dart';

/// Shared body of the non-rank buttons: label never ellipsizes and never
/// splits a word (scales down to 80 %, then wraps at a space and the button
/// grows), busy = spinner inside, disabled =
/// 45 % opacity, press = .97 + haptic, `Semantics(button)`.
class _MgButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final Color fill;
  final Color fg;
  final BoxBorder? border;
  final double height;
  final bool busy;
  final bool expand;
  final TextStyle style;

  const _MgButton({
    required this.label,
    required this.onTap,
    required this.fill,
    required this.fg,
    this.icon,
    this.border,
    this.height = MgSize.button,
    this.busy = false,
    this.expand = true,
    this.style = MgType.button,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[MgIcon(icon!, size: 20, color: fg), const SizedBox(width: 8)],
        Flexible(
          // Nikdy nezalomit uprostřed slova („Bearbeit|en"): nejdřív zmenšit
          // (do 80 %), teprve pak zalomit v mezeře.
          child: MgWordFit(
            alignment: Alignment.center,
            child: Text(label,
                textAlign: TextAlign.center,
                softWrap: true,
                style: style.copyWith(color: fg)),
          ),
        ),
      ],
    );
    if (busy) {
      content = Stack(alignment: Alignment.center, children: [
        Opacity(opacity: 0, child: content),
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg)),
      ]);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: MgPress(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Container(
            width: expand ? double.infinity : null,
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(MgRadius.button),
              border: border,
            ),
            alignment: expand ? Alignment.center : null,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Primary / secondary action ON LIGHT: ink `#1A2E22` + white (or neon) label.
class MgBtnInk extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool neonLabel;
  final double height;
  final bool busy;
  final bool expand;
  const MgBtnInk({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.neonLabel = false,
    this.height = MgSize.button,
    this.busy = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) => _MgButton(
        label: label,
        onTap: onTap,
        icon: icon,
        fill: MgColors.ink,
        fg: neonLabel ? MgColors.neon : MgColors.onDark,
        height: height,
        busy: busy,
        expand: expand,
      );
}

/// Secondary on light: white, 1.5 px `#0D6E0D`, green label.
class MgBtnGhostLight extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final double height;
  final bool busy;
  final bool expand;
  const MgBtnGhostLight({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 48,
    this.busy = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) => _MgButton(
        label: label,
        onTap: onTap,
        icon: icon,
        fill: MgColors.surface,
        fg: MgColors.link,
        border: Border.all(color: MgColors.link, width: 1.5),
        height: height,
        busy: busy,
        expand: expand,
      );
}

/// Secondary on dark: white .05 glass, neon .6 border, white label.
class MgBtnGhostDark extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final double height;
  final bool expand;
  const MgBtnGhostDark({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 48,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) => _MgButton(
        label: label,
        onTap: onTap,
        icon: icon,
        fill: MgColors.white(0.05),
        fg: MgColors.onDark,
        border: Border.all(color: MgColors.neonA(0.6), width: 1.5),
        height: height,
        expand: expand,
      );
}

/// Destructive (storno, delete): `#B42318` fill, or text-only variant.
class MgBtnDestructive extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;
  final bool expand;
  final double height;
  const MgBtnDestructive({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.busy = false,
    this.expand = true,
    this.height = MgSize.button,
  });

  @override
  Widget build(BuildContext context) => _MgButton(
        label: label,
        onTap: onTap,
        fill: filled ? MgColors.err : const Color(0x00000000),
        fg: filled ? MgColors.onDark : MgColors.err,
        height: filled ? height : MgSize.touch,
        busy: busy,
        expand: expand,
      );
}

/// SOS action: `#D92D20` + white (4.83 : 1). Never rank-coloured.
class MgBtnSos extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final bool expand;
  const MgBtnSos({
    super.key,
    required this.label,
    required this.onTap,
    this.height = MgSize.button,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) => _MgButton(
        label: label,
        onTap: onTap,
        icon: MgIcons.alert,
        fill: MgColors.sos,
        fg: MgColors.onDark,
        height: height,
        expand: expand,
      );
}

/// Tertiary text action (`#0D6E0D` on light, neon text on dark), 44 tall.
class MgBtnText extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool dark;
  final Color? color;
  const MgBtnText({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.dark = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) => _MgButton(
        label: label,
        onTap: onTap,
        icon: icon,
        fill: const Color(0x00000000),
        fg: color ?? (dark ? MgColors.neonText : MgColors.link),
        height: MgSize.touch,
        expand: false,
        style: MgType.small.copyWith(fontWeight: FontWeight.w800),
      );
}

enum MgIconButtonStyle { dark, light, photo }

/// 44 px icon disc (hit 48): dark glass / light white + line / photo scrim.
/// Icon-only → [semanticLabel] is required.
class MgIconButton extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final MgIconButtonStyle style;
  final double size;
  final int badge;
  final Color? iconColor;
  const MgIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.style = MgIconButtonStyle.dark,
    this.size = MgSize.touch,
    this.badge = 0,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final (fill, border, fg, shadow) = switch (style) {
      MgIconButtonStyle.dark => (MgColors.white(0.10), MgColors.white(0.25), MgColors.onDark, null),
      MgIconButtonStyle.light => (MgColors.surface, MgColors.line, MgColors.ink, MgShadows.icon),
      MgIconButtonStyle.photo => (MgColors.nightA(0.80), MgColors.white(0.25), MgColors.onDark, MgShadows.photoControl),
    };
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        scale: 0.92,
        onTap: onTap,
        child: SizedBox(
          width: size + 4,
          height: size + 4,
          child: Center(
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                  boxShadow: shadow,
                ),
                child: Center(child: MgIcon(icon, size: size * 0.5, color: iconColor ?? fg)),
              ),
              if (badge > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MgColors.sos,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: MgColors.night, width: 2),
                    ),
                    child: Text(badge > 9 ? '9+' : '$badge',
                        style: MgType.tab(MgType.micro.copyWith(
                            fontWeight: FontWeight.w800, height: 1, color: MgColors.onDark))),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
