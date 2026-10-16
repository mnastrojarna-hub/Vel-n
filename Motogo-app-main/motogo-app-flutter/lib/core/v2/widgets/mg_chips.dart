import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../rank/rank_provider.dart';
import '../rank/rank_tokens.dart';
import '../states/mg_tone.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';

export '../states/mg_tone.dart' show MgTone;

/// Choice chip on light (44): well → selected = ink fill + neon text (+ ✓),
/// so the selection is never colour-only.
class MgChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? icon;
  final String? sub;
  const MgChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? MgColors.neon : MgColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: sub == null ? label : '$label, $sub',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MgMotion.of(context, MgMotion.color),
          constraints: const BoxConstraints(minHeight: MgSize.choiceChip),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? MgColors.ink : MgColors.well,
            borderRadius: BorderRadius.circular(MgRadius.button),
            border: Border.all(color: selected ? MgColors.ink : MgColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected) ...[
              MgPop(trigger: selected, child: MgIcon(MgIcons.check, size: 16, color: fg)),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              MgIcon(icon!, size: 16, color: MgColors.link),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
                  if (sub != null)
                    Text(sub!,
                        style: MgType.meta.copyWith(
                            color: selected ? MgColors.onDarkLead : MgColors.meta)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Filter chip on light: white + line, optional count in a well pill.
class MgFilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;
  final String? icon;
  const MgFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: MgSize.chip),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? MgColors.tintOk : MgColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? MgColors.tintOkBorder : MgColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[MgIcon(icon!, size: 16, color: MgColors.link), const SizedBox(width: 6)],
            Flexible(
              child: Text(label,
                  style: MgType.small.copyWith(
                      fontWeight: FontWeight.w800, color: selected ? MgColors.onTintOk : MgColors.ink)),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: MgColors.well,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.line),
                ),
                child: Text('$count', style: MgType.tab(MgType.meta.copyWith(color: MgColors.ink))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Rank chip: ALWAYS a dark pill with a rank-colour dot. On dark the text is
/// the rank chip text (≥ 4.5 : 1); on light the pill stays dark with white
/// text (rank text on light is never rank-coloured, V22 §1.4).
class MgRankChip extends ConsumerWidget {
  final String label;
  final bool onLight;
  final VoidCallback? onTap;
  final RankTokens? rank;
  final String? semanticLabel;
  const MgRankChip({
    super.key,
    required this.label,
    this.onLight = false,
    this.onTap,
    this.rank,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RankTokens r = rank ?? ref.watch(rankTokensProvider);
    final chip = Container(
      height: 28,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      decoration: BoxDecoration(
        color: onLight ? MgColors.panel : r.chipBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: r.chipBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: r.hex,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: r.glowColor.withValues(alpha: r.row.glowAlpha), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: MgType.meta.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: onLight ? MgColors.onDark : r.chipText)),
        ),
      ]),
    );
    final sem = Semantics(
      button: onTap != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null
          ? chip
          : MgPress(onTap: onTap, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: Center(widthFactor: 1, child: chip))),
    );
    return sem;
  }
}

/// Meaning chip (✓ Zaplaceno, ⚠ Chybí doklady…): icon + text, never only
/// colour.
class MgMeaningChip extends StatelessWidget {
  final String label;
  final MgTone tone;
  final String? icon;
  final bool dark;
  const MgMeaningChip({super.key, required this.label, required this.tone, this.icon, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border, ic) = mgToneChipColors(tone, dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        MgIcon(icon ?? ic, size: 14, color: fg),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: fg))),
      ]),
    );
  }
}

/// (background, foreground, border, default icon) of a tone chip.
(Color, Color, Color?, String) mgToneChipColors(MgTone tone, bool dark) => switch (tone) {
      MgTone.ok => dark
          ? (MgColors.neonA(0.14), MgColors.neon, MgColors.neonA(0.35), MgIcons.check)
          : (MgColors.tintOk, MgColors.onTintOk, MgColors.tintOkBorder, MgIcons.check),
      MgTone.warn || MgTone.pending => dark
          ? (MgColors.warnDarkBg, MgColors.warnDark, null, tone == MgTone.warn ? MgIcons.warn : MgIcons.clock)
          : (MgColors.warnBg, MgColors.warn, MgColors.warnBorder, tone == MgTone.warn ? MgIcons.warn : MgIcons.clock),
      MgTone.err => dark
          ? (MgColors.errDarkBg, MgColors.errDark, null, MgIcons.xCircle)
          : (MgColors.errBg, MgColors.err, MgColors.errBorder, MgIcons.xCircle),
      MgTone.info => dark
          ? (MgColors.white(0.10), MgColors.onDark, null, MgIcons.info)
          : (MgColors.well, MgColors.ink, MgColors.line, MgIcons.info),
      MgTone.sos => (MgColors.sos, MgColors.onDark, null, MgIcons.alert),
    };

/// Small r6 tag (category, "ukázka", "návrh").
class MgTag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const MgTag(this.label, {super.key, this.background = MgColors.well, this.foreground = MgColors.ink});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(MgRadius.tag)),
        child: Text(label, style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: foreground)),
      );
}
