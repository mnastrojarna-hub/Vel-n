import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'moto_filter_chips_v2.dart';

/// v2 look of the INLINE `MotoFilterPanel` (Motorky, Domů). 5.0.1 (owner):
/// folded, it is either CALM ("Filtr motorek" · "Všechny motorky — vyber
/// typ, ŘP nebo výkon") or, with real filters on ([active] > 0 — never the
/// dates or the branch), LOUD: a green card "Filtry zapnuté (n)", "Nevidíš
/// všechny motorky", every filter as a chip with ✕ and "Zrušit vše". The
/// branch ("kam vyrážím") is a pin chip with ✕ in both states. A tap
/// anywhere else opens the panel as before; open, [body] (on Domů first
/// "TERMÍN · [datesValue]" + [calendar]). Every value and closure is the
/// panel state's; it starts folded as before ([open] comes from the state).
class MotoFilterCardV2 extends StatelessWidget {
  final bool open;

  /// Real filters on (`CatalogFilter.filterCount`).
  final int active;
  final VoidCallback onToggle;

  /// "Zrušit vše": clears exactly what [active] counts.
  final VoidCallback onReset;

  /// Removable chips (`motoFilterChips`), shown while folded.
  final List<MotoFilterChipItem> chips;

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
    this.chips = const [],
    this.datesValue,
    this.calendar,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final on = active > 0;
    final title = on ? tr.trArgs('motoFltOn', {'n': active}) : tr.tr('homeFilterTitle');
    final sub = on ? tr.tr('motoFltOnHint') : '${tr.tr('motoFltAll')} · ${tr.tr('motoFltHint')}';
    final dur = MgMotion.of(context, MgMotion.color);
    final header = Semantics(
      button: true,
      expanded: open,
      label: '$title. $sub',
      excludeSemantics: true,
      onTap: onToggle,
      child: MgPress(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(children: [
            _Badge(on: on, duration: dur),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                MgWordFit(
                  minScale: 0.75,
                  child: Text(title,
                      maxLines: 1,
                      style: (on ? MgType.section : MgType.title).copyWith(color: on ? MgColors.link : MgColors.ink)),
                ),
                const SizedBox(height: 2),
                // Calm: "Všechny motorky" in ink, the invitation after it.
                Text.rich(
                  on
                      ? TextSpan(text: sub)
                      : TextSpan(children: [
                          TextSpan(
                              text: tr.tr('motoFltAll'),
                              style: const TextStyle(color: MgColors.ink, fontWeight: FontWeight.w800)),
                          TextSpan(text: ' · ${tr.tr('motoFltHint')}'),
                        ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.small.copyWith(
                      color: on ? MgColors.onTintOk : MgColors.meta, fontWeight: on ? FontWeight.w700 : FontWeight.w600),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: dur,
              child: MgIcon(MgIcons.chevronDown, size: 22, color: on ? MgColors.link : MgColors.meta),
            ),
          ]),
        ),
      ),
    );
    final shown = open ? const <MotoFilterChipItem>[] : chips;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AnimatedContainer(
        key: const ValueKey('moto-filter-card'),
        duration: dur,
        padding: const EdgeInsets.fromLTRB(MgSpace.card - 2, 8, MgSpace.card - 2, 10),
        decoration: BoxDecoration(
          color: on ? MgColors.tintOk : MgColors.surface,
          borderRadius: BorderRadius.circular(MgRadius.card),
          border: Border.all(color: on ? MgColors.link : MgColors.line, width: on ? 2 : 1),
          boxShadow: MgShadows.card,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          if (shown.isNotEmpty || on)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final c in shown) _Chip(item: c, remove: tr.trArgs('motoFltRemove', {'f': c.label})),
                if (on) _ClearAll(label: tr.tr('motoFltClear'), onTap: onReset),
              ]),
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

/// 40 px icon disc: calm = light well + green filter icon; on = the neon
/// gradient with a soft glow and the dark filter icon.
class _Badge extends StatelessWidget {
  final bool on;
  final Duration duration;
  const _Badge({required this.on, required this.duration});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: duration,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? null : MgColors.well,
          gradient: on ? MgGradients.neon : null,
          border: Border.all(color: on ? MgColors.link : MgColors.line, width: on ? 1.5 : 1),
          boxShadow: on ? const [BoxShadow(color: Color(0x5537CF63), blurRadius: 12, offset: Offset(0, 3))] : null,
        ),
        child: Center(child: MgIcon(MgIcons.filter, size: 20, color: on ? MgColors.onNeon : MgColors.link)),
      );
}

/// A removable filter chip: ink pill + white text + neon ✕ (the branch: a
/// light pin chip). The whole chip is the ✕ target (≥ 40 px high).
class _Chip extends StatelessWidget {
  final MotoFilterChipItem item;
  final String remove;
  const _Chip({required this.item, required this.remove});

  @override
  Widget build(BuildContext context) {
    final place = item.place;
    final fg = place ? MgColors.onTintOk : MgColors.onDark;
    return Semantics(
      button: true,
      label: remove,
      excludeSemantics: true,
      onTap: item.onRemove,
      child: MgPress(
        onTap: item.onRemove,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
          decoration: BoxDecoration(
            color: place ? MgColors.surface : MgColors.ink,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: place ? MgColors.tintOkBorder : MgColors.ink, width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (place) ...[MgIcon(MgIcons.pin, size: 15, color: MgColors.link), const SizedBox(width: 4)],
            Flexible(
              child: Text(item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
            ),
            const SizedBox(width: 6),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: place ? MgColors.well : MgColors.neon,
              ),
              child: Center(child: MgIcon(MgIcons.close, size: 13, stroke: 2.6, color: place ? MgColors.ink : MgColors.onNeon)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Zrušit vše": a clear text action with ✕ in the brand green.
class _ClearAll extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ClearAll({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          key: const ValueKey('moto-filter-clear'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                MgIcon(MgIcons.close, size: 16, color: MgColors.link),
                const SizedBox(width: 4),
                Text(label,
                    style: MgType.small.copyWith(
                        fontWeight: FontWeight.w800, color: MgColors.link, decoration: TextDecoration.underline, decorationColor: MgColors.link)),
              ]),
            ),
          ),
        ),
      );
}
