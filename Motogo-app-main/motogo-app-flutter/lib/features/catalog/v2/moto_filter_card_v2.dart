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
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'moto_filter_chips_v2.dart';

/// v2 look of the INLINE `MotoFilterPanel` (Motorky, Domů). 5.0.1 (owner):
/// folded, it is either CALM (dark neon tile, "Filtr motorek" · "Všechny
/// motorky", an ink "Filtrovat" pill) or, with real filters on ([active]
/// > 0 — never the dates or the branch), LOUD: a green card "Filtry
/// zapnuté (n)", "Nevidíš všechny motorky", every filter as a chip with ✕
/// (one sideways row) and "Zrušit vše". The branch ("kam vyrážím") is a pin chip with ✕ in both states. A tap
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
    final hasPlace = chips.any((c) => c.place);
    final title = on ? tr.trArgs('motoFltOn', {'n': active}) : tr.tr('homeFilterTitle');
    // Calm: "Všechny motorky" — or, with a branch chip under it, "Motorky na
    // pobočce" (the heading and the list agree).
    final sub = on ? tr.tr('motoFltOnHint') : tr.tr(hasPlace ? 'motoFltAtBranch' : 'motoFltAll');
    final dur = MgMotion.of(context, MgMotion.color);
    final chevron = AnimatedRotation(
      turns: open ? 0.5 : 0,
      duration: dur,
      child: MgIcon(MgIcons.chevronDown, size: 22, color: on ? MgColors.link : MgColors.meta),
    );
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
            on ? _Badge(duration: dur) : const MgIconTileDark(MgIcons.filter),
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
                MgWordFit(
                  minScale: 0.8,
                  fitLines: 1,
                  child: Text(sub,
                      maxLines: 3,
                      style: MgType.small.copyWith(
                          color: on ? MgColors.onTintOk : MgColors.body2, fontWeight: on ? FontWeight.w700 : FontWeight.w800)),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            if (on || open) chevron else _FilterPill(label: tr.tr('motoFltFilter')),
          ]),
        ),
      ),
    );
    final shown = open ? const <MotoFilterChipItem>[] : chips;
    final clear = on ? MotoFilterClearAllV2(label: tr.tr('motoFltClear'), onTap: onReset) : null;
    Widget? chipRow;
    if (shown.isNotEmpty) {
      // One row: the chips scroll sideways, "Zrušit vše" stays on the right.
      chipRow = Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            child: Row(children: [
              for (final c in shown) ...[
                MotoFilterChipV2(item: c, removeLabel: tr.trArgs('motoFltRemove', {'f': c.label}), onOpen: onToggle),
                const SizedBox(width: 8),
              ],
            ]),
          ),
        ),
        if (clear != null) clear,
      ]);
    } else if (clear != null) {
      chipRow = Align(alignment: AlignmentDirectional.centerEnd, child: clear);
    }
    // A tap anywhere on the folded part (padding included) opens the panel;
    // the chips' ✕ and "Zrušit vše" keep their own taps.
    final folded = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (chipRow != null) Padding(padding: const EdgeInsets.only(top: 6), child: chipRow),
      ]),
    );
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
          folded,
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

/// "Filtrovat": the calm card's action — an ink pill with a neon icon (the
/// routes toolbar "Filtry" look). Part of the header tap (opens the panel).
class _FilterPill extends StatelessWidget {
  final String label;
  const _FilterPill({required this.label});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(minHeight: 40, maxWidth: MediaQuery.sizeOf(context).width * 0.4),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 14, 8),
          decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            MgIcon(MgIcons.filter, size: 16, color: MgColors.neon),
            const SizedBox(width: 6),
            Flexible(
              child: MgWordFit(
                minScale: 0.7,
                fitLines: 1,
                child: Text(label,
                    maxLines: 1,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
              ),
            ),
          ]),
        ),
      );
}

/// 40 px icon disc of the loud state: the neon gradient with a soft glow
/// and the dark filter icon (calm = `MgIconTileDark`, like the rows above).
class _Badge extends StatelessWidget {
  final Duration duration;
  const _Badge({required this.duration});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: duration,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: MgGradients.neon,
          border: Border.all(color: MgColors.link, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x5537CF63), blurRadius: 12, offset: Offset(0, 3))],
        ),
        child: Center(child: MgIcon(MgIcons.filter, size: 20, color: MgColors.onNeon)),
      );
}
