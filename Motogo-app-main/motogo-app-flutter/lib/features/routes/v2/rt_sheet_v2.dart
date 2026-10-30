import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Light v2 chrome of the Trasy / Místa tool sheets (board TrasyHub
/// `.shl`, V22 §6.1 / R5.10): grabber 42 × 5, title + 44 px ✕, scrolling
/// body, pinned [footer] with the optional red "Zrušit" link under it (in
/// the title row it split mid-word at 320 px / large text). Built inside
/// the screens' existing `showModalBottomSheet` builders, so their working
/// copies, counts and callbacks stay where they are.
class RtSheetV2 extends StatelessWidget {
  final String title;
  final Widget child;

  /// "Zrušit filtry" (null = no link): the screen's existing reset + close.
  final String? clearLabel;
  final VoidCallback? onClear;
  final Widget? footer;

  /// false = [child] scrolls by itself (lazy lists).
  final bool scroll;
  final EdgeInsetsGeometry padding;
  const RtSheetV2({
    super.key,
    required this.title,
    required this.child,
    this.clearLabel,
    this.onClear,
    this.footer,
    this.scroll = true,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final clear = clearLabel != null && onClear != null;
    final body = scroll
        ? SingleChildScrollView(padding: padding, child: child)
        : Padding(padding: padding, child: child);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: (mq.size.height - mq.padding.top) * 0.86),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(MgRadius.sheet)),
            boxShadow: MgShadows.sheet,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(color: MgColors.grabberLight, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                child: Row(children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: MgWordFit(minScale: 0.75, child: Text(title, style: MgType.h3.copyWith(color: MgColors.ink))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MgV2Back(close: true, style: MgBackStyle.light, onTap: () => Navigator.of(context).maybePop()),
                ]),
              ),
              Flexible(child: body),
              if (footer != null)
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, (clear ? 2 : 12) + mq.padding.bottom),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: MgColors.line))),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    footer!,
                    if (clear) Center(child: MgBtnText(label: clearLabel!, onTap: onClear, color: MgColors.err)),
                  ]),
                )
              else
                SizedBox(height: mq.padding.bottom),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Section title of a tool sheet (`.sh-st`): 15/800 ink, optional value on
/// the right ("40–250 km").
class RtSectionV2 extends StatelessWidget {
  final String title;
  final String? value;
  final double top;
  const RtSectionV2(this.title, {super.key, this.value, this.top = 20});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 10),
        child: Semantics(
          header: true,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: MgWordFit(child: Text(title, style: MgType.title.copyWith(color: MgColors.ink)))),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(value!, style: MgType.tab(MgType.title.copyWith(color: MgColors.link))),
            ],
          ]),
        ),
      );
}

/// "Další státy (6)" / "Minimální hodnocení" — a green link with a chevron
/// that opens / closes the part below (44 tall).
class RtExpandLinkV2 extends StatelessWidget {
  final String label;
  final bool open;
  final VoidCallback onTap;
  const RtExpandLinkV2({super.key, required this.label, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        expanded: open,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MgSize.touch),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: MgWordFit(
                  child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: MgMotion.reduced(context) ? Duration.zero : MgMotion.color,
                child: const MgIcon(MgIcons.chevronDown, size: 16, color: MgColors.link),
              ),
            ]),
          ),
        ),
      );
}

/// Light search field of a sheet (`.srch.lt`): v2 input + 🔍 + ✕ (clears).
class RtSearchV2 extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool showClear;
  final VoidCallback onClear;
  const RtSearchV2({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.showClear,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: MgType.body.copyWith(color: MgColors.ink),
        decoration: mgInputDecoration(
          context,
          hint: hint,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 12, right: 8),
            child: MgIcon(MgIcons.search, size: 20, color: MgColors.meta),
          ),
          suffixIcon: showClear
              ? MgIconButton(
                  icon: MgIcons.close,
                  onTap: onClear,
                  style: MgIconButtonStyle.light,
                  size: 32,
                  semanticLabel: t(context).tr('v2RtSearchClear'),
                )
              : null,
        ).copyWith(prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40)),
      );
}
