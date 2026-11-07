import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_animated_size.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';

/// One-tap disclosure (owner rule 2026-10-16, design D7): optional extras,
/// secondary details, long texts and "Technické detaily" start collapsed.
/// Header = [summary] + text button [label] (≥ 44 px) + chevron rotating
/// 180° over `MgMotion.color`; the body opens with `MgAnimatedSize`
/// (`MgMotion.sheet`, emphasized). [forceExpanded] (a blocker inside) opens
/// it and keeps it open after the flag drops, until the customer collapses
/// it. Reduced motion: instant.
class MgDisclosure extends StatefulWidget {
  final String label;
  final String? expandedLabel;
  final Widget? summary;
  final Widget child;
  final bool initiallyExpanded;
  final bool forceExpanded;
  final ValueChanged<bool>? onChanged;
  final bool dark;
  final EdgeInsetsGeometry padding;

  const MgDisclosure({
    super.key,
    required this.label,
    this.expandedLabel,
    this.summary,
    required this.child,
    this.initiallyExpanded = false,
    this.forceExpanded = false,
    this.onChanged,
    this.dark = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<MgDisclosure> createState() => _MgDisclosureState();
}

class _MgDisclosureState extends State<MgDisclosure> {
  late bool _open = widget.initiallyExpanded || widget.forceExpanded;

  @override
  void didUpdateWidget(covariant MgDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceExpanded && !oldWidget.forceExpanded && !_open) {
      _open = true;
      widget.onChanged?.call(true);
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    widget.onChanged?.call(_open);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? MgColors.neonText : MgColors.link;
    final label = _open ? (widget.expandedLabel ?? widget.label) : widget.label;
    final header = Semantics(
      button: true,
      expanded: _open,
      label: label,
      excludeSemantics: widget.summary == null,
      onTap: _toggle,
      child: MgPress(
        onTap: _toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: MgSize.touch),
          child: Row(children: [
            if (widget.summary != null) ...[Expanded(child: widget.summary!), const SizedBox(width: MgSpace.s8)],
            Flexible(
              child: Text(label,
                  textAlign: widget.summary == null ? TextAlign.start : TextAlign.end,
                  style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: MgMotion.of(context, MgMotion.color),
              child: MgIcon(MgIcons.chevronDown, size: 18, color: fg),
            ),
          ]),
        ),
      ),
    );
    return Padding(
      padding: widget.padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        header,
        MgAnimatedSize(
          duration: MgMotion.sheet,
          curve: MgMotion.emphasized,
          alignment: Alignment.topCenter,
          child: _open ? widget.child : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}
