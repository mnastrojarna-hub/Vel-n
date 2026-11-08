import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// v2 look of the INLINE `MotoFilterPanel` (Motorky, Domů): the old
/// collapsible card — header "Filtry" (+ active count, "Resetovat", chevron)
/// toggles the panel, folded it still shows the chosen branch — and, open,
/// [body] (the panel's own v2 content `MotoFilterPanelV2View`; on Domů
/// first "TERMÍN · [datesValue]" + [calendar], as the old panel had). Every value and closure is the panel state's;
/// it starts folded as before ([open] comes from the state).
class MotoFilterCardV2 extends StatelessWidget {
  final bool open;
  final int active;
  final VoidCallback onToggle;
  final VoidCallback onReset;

  /// Chosen branch name (the old `FilterBranchChip` under the folded header).
  final String? branchName;

  /// Domů only (`showDates`): the old "Termín" label value + its calendar.
  final String? datesValue;
  final Widget? calendar;
  final Widget body;

  const MotoFilterCardV2({
    super.key,
    required this.open,
    required this.active,
    required this.onToggle,
    required this.onReset,
    required this.body,
    this.branchName,
    this.datesValue,
    this.calendar,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final title = tr.tr('homeFilterTitle');
    final header = Semantics(
      button: true,
      expanded: open,
      label: active > 0 ? '$title · $active' : title,
      excludeSemantics: true,
      onTap: onToggle,
      child: MgPress(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(children: [
            MgIcon(MgIcons.filter, size: 20, color: MgColors.link),
            const SizedBox(width: 8),
            Flexible(
              child: MgWordFit(minScale: 0.8, child: Text(title, style: MgType.title.copyWith(color: MgColors.ink))),
            ),
            if (active > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
                child: Text('$active', style: MgType.tab(MgType.micro.copyWith(color: MgColors.neon))),
              ),
            ],
            const Spacer(),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: MgMotion.of(context, MgMotion.color),
              child: MgIcon(MgIcons.chevronDown, size: 22, color: MgColors.meta),
            ),
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: MgCard(
        key: const ValueKey('moto-filter-card'),
        padding: const EdgeInsets.fromLTRB(MgSpace.card, 6, MgSpace.card, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          if (active > 0)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MgBtnText(label: tr.tr('homeFilterReset'), icon: MgIcons.close, onTap: onReset),
            ),
          if (!open && branchName != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MgPress(
                onTap: onToggle,
                child: Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: MgColors.tintOk,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MgColors.tintOkBorder),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    MgIcon(MgIcons.pin, size: 15, color: MgColors.link),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('${tr.tr('branchPrefix')}: $branchName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk)),
                    ),
                  ]),
                ),
              ),
            ),
          // MgAnimatedSize: no layout assert when the duration is 0 (reduced motion).
          MgAnimatedSize(
            duration: MgMotion.of(context, MgMotion.sheet),
            curve: MgMotion.out,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (calendar != null) ...[
                        Row(children: [
                          Expanded(
                            child: Text(tr.tr('homeFilterDates').toUpperCase(),
                                style: MgType.eyebrow.copyWith(color: MgColors.meta)),
                          ),
                          if (datesValue != null)
                            Text(datesValue!, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
                        ]),
                        const SizedBox(height: 8),
                        calendar!,
                        const SizedBox(height: 16),
                      ],
                      body,
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}
