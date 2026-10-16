import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_buttons.dart';
import '../widgets/mg_chips.dart';
import '../widgets/mg_sheet.dart';
import 'mg_state_parts.dart';
import 'mg_support_row.dart';
import 'mg_tech_details.dart';
import 'mg_tone.dart';

/// A reassurance / context chip of a T2 sheet ("Pokus 2 ze 3", ✓ "Nic jsme
/// nestrhli") — only facts the caller already knows.
class MgStateChip {
  final String label;
  final MgTone tone;
  const MgStateChip(this.label, [this.tone = MgTone.info]);
}

/// T2 body: tone disc 56 + chips, title 20/800 (2 lines), why, ≤ 3 steps,
/// support row, technical details. Buttons are pinned by the sheet frame.
class MgStateSheetBody extends StatelessWidget {
  final MgTone tone;
  final String title;
  final String? why;
  final List<String> steps;
  final List<MgStateChip> chips;
  final String? tech;
  final bool support;
  final VoidCallback? onWrite;
  final String? icon;
  final List<Widget> children;

  const MgStateSheetBody({
    super.key,
    required this.tone,
    required this.title,
    this.why,
    this.steps = const [],
    this.chips = const [],
    this.tech,
    this.support = true,
    this.onWrite,
    this.icon,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        MgToneDisc(tone: tone, size: 56, icon: icon),
        if (chips.isNotEmpty) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in chips) MgMeaningChip(label: c.label, tone: c.tone),
            ]),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(title, style: MgType.h3.copyWith(color: MgColors.ink)),
      ),
      if (why != null) ...[
        const SizedBox(height: 8),
        Text(why!, style: MgType.body.copyWith(color: MgColors.body2)),
      ],
      for (final c in children) ...[const SizedBox(height: MgSpace.s12), c],
      if (steps.isNotEmpty) ...[
        const SizedBox(height: 14),
        MgStateSteps(steps: steps.take(3).toList(), compact: true),
      ],
      if (support) ...[const SizedBox(height: 12), MgSupportRow(onWrite: onWrite)],
      if (tech != null) ...[const SizedBox(height: 4), MgTechDetails(details: tech!)],
    ]);
  }
}

/// Opens a T2 result sheet (light, ✕ 44, max 86 %, buttons pinned).
/// Buttons call the caller's callbacks; when a callback is null the button
/// just closes the sheet.
Future<T?> showMgStateSheet<T>(
  BuildContext context, {
  required MgTone tone,
  required String title,
  String? why,
  List<String> steps = const [],
  List<MgStateChip> chips = const [],
  String? tech,
  bool support = true,
  MgStateAction? primary,
  MgStateAction? secondary,
  MgStateAction? tertiary,
  bool isDismissible = true,
  String? icon,
}) {
  return showMgSheet<T>(
    context,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    builder: (_) => MgStateSheetBody(
      tone: tone,
      title: title,
      why: why,
      steps: steps,
      chips: chips,
      tech: tech,
      support: support,
      icon: icon,
    ),
    footer: primary == null && secondary == null && tertiary == null
        ? null
        : Builder(builder: (ctx) {
            VoidCallback? wrap(MgStateAction a) =>
                a.onTap ?? () => Navigator.of(ctx).maybePop();
            return MgSheetButtons(
              primary: primary == null
                  ? const SizedBox.shrink()
                  : (primary.destructive
                      ? MgBtnDestructive(label: primary.label, onTap: wrap(primary), busy: primary.busy)
                      : (primary.sos
                          ? MgBtnSos(label: primary.label, onTap: wrap(primary))
                          : MgBtnInk(label: primary.label, onTap: wrap(primary), busy: primary.busy))),
              secondary: secondary == null
                  ? null
                  : MgBtnGhostLight(label: secondary.label, onTap: wrap(secondary)),
              tertiary: tertiary == null ? null : MgBtnText(label: tertiary.label, onTap: wrap(tertiary)),
            );
          }),
  );
}
