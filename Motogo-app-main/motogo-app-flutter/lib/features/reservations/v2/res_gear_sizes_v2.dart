import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../gear/gear_edit_view.dart';

/// v2 sekce „Změnit velikosti“ výpůjčky výbavy (web záložka Velikosti):
/// kus → řada velikostí (vybraná = ink + neon fajfka, vyprodaná přeškrtnutá
/// a neaktivní), poznámka o limitech samoobsluhy, jedno CTA „Uložit“.
class ResGearSizesV2 extends StatelessWidget {
  final GearEditData data;
  final GearEditActions actions;
  const ResGearSizesV2({super.key, required this.data, required this.actions});

  static String gearIcon(String key) => switch (key) {
        'helmet' => MgIcons.helmet,
        'jacket' => MgIcons.jacket,
        'pants' => MgIcons.pants,
        'gloves' => MgIcons.glove,
        'boots' => MgIcons.boot,
        _ => MgIcons.ruler,
      };

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rows = data.sizes ?? const <GearSizeRowData>[];
    return MgCard(
      key: const ValueKey('gear-sizes-v2'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr.tr('gearSizesTitle'), style: MgType.title.copyWith(color: MgColors.ink)),
        const SizedBox(height: 4),
        Text(tr.tr('gearSizesIntro'), style: MgType.small.copyWith(color: MgColors.lead)),
        if (data.selfService) ...[
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: MgIcon(MgIcons.info, size: 16, color: MgColors.meta)),
            const SizedBox(width: 6),
            Expanded(child: Text(tr.tr('gearSsLimits'), style: MgType.small.copyWith(color: MgColors.meta))),
          ]),
        ],
        for (final r in rows) ...[
          const SizedBox(height: 14),
          Row(children: [
            MgIcon(gearIcon(r.key), size: 18, color: MgColors.link),
            const SizedBox(width: 8),
            Expanded(child: Text(r.label, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in r.sizes)
              _Chip(
                key: ValueKey('gear-size-${r.key}-$s'),
                label: s,
                selected: r.selected == s,
                soldOut: r.soldOut.contains(s),
                soldOutLabel: tr.tr('gearSoldOut'),
                onTap: data.busy ? null : () => actions.onPickSize(r.key, s),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        Text(tr.tr(data.sizesChanged ? 'gearSizesFree' : 'gearSizesPick'),
            style: MgType.small.copyWith(color: data.sizesChanged ? MgColors.link : MgColors.meta, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        MgCta(
          key: const ValueKey('gear-sizes-save'),
          label: tr.tr('gearSizesSave'),
          size: MgCtaSize.sm48,
          showMarks: false,
          enabled: data.sizesChanged && !data.busy,
          busy: data.busy,
          onTap: actions.onSaveSizes,
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool soldOut;
  final String soldOutLabel;
  final VoidCallback? onTap;
  const _Chip({super.key, required this.label, required this.selected, required this.soldOut, required this.soldOutLabel, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tap = soldOut ? null : onTap;
    return Semantics(
      button: true,
      selected: selected,
      enabled: tap != null,
      label: soldOut ? '$label, $soldOutLabel' : label,
      excludeSemantics: true,
      child: MgPress(
        onTap: tap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? MgColors.ink : MgColors.well,
            borderRadius: BorderRadius.circular(MgRadius.action),
            border: Border.all(color: selected ? MgColors.ink : MgColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (selected) ...[
              const MgIcon(MgIcons.check, size: 14, color: MgColors.neon, stroke: 2.6),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: MgType.body.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected ? MgColors.onDark : (soldOut ? MgColors.meta : MgColors.ink),
                  decoration: soldOut ? TextDecoration.lineThrough : null,
                )),
          ]),
        ),
      ),
    );
  }
}
