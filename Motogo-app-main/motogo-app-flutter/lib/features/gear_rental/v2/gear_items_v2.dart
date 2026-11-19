import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../booking/v2/booking_v2_parts.dart' show BkCard, BkSizeChip, bkNb;
import '../gear_contract.dart';
import '../gear_order_state.dart';
import '../gear_order_ui.dart';
import '../gear_quote.dart';
import 'gear_branch_v2.dart' show GearNoteV2;

/// Krok 3 „Výbava a velikosti“: tlačítka kompletů (stisknuté = vybrané
/// přesně jejich kusy), kusy se zaškrtnutím a cenou za den, u vybraného
/// kusu velikosti (samoobsluha jen rozsah kiosku, obsazené vypnuté).
class GearItemsV2 extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  final void Function(String key, bool on) onToggleItem;
  final void Function(String key) onToggleSet;
  const GearItemsV2({super.key, required this.state, required this.ctrl, required this.onToggleItem, required this.onToggleSet});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final prices = state.prices;
    return BkCard(
      key: const ValueKey('gear-step-items'),
      icon: MgIcons.helmet,
      title: tr.tr('groStepGear'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr.tr('groGearHint'), style: MgType.small.copyWith(color: MgColors.lead)),
        const SizedBox(height: 10),
        for (final s in gearSetsOf(prices)) ...[
          GearSetButtonV2(set: s, on: gearSetOn(s, prices, state.sel), onTap: () => onToggleSet(s.key)),
          const SizedBox(height: 8),
        ],
        for (final m in state.drops)
          GearNoteV2(m.text(tr), key: const ValueKey('gear-size-dropped'), color: MgColors.warn, icon: MgIcons.warn),
        const SizedBox(height: 4),
        for (final p in gearItemsOf(prices)) _item(context, tr, p),
        if (state.isSelf) GearNoteV2(tr.tr('groSsCapNote')),
      ]),
    );
  }

  Widget _item(BuildContext context, AppTranslations tr, GearPrice p) {
    final on = state.sel.containsKey(p.key);
    final sz = state.sel[p.key] ?? '';
    final list = gearSizesFor(p, state.isSelf);
    final price = bkNb('${gearMoney(p.perDay)} ${tr.tr('groPerDay')}');
    return Container(
      key: ValueKey('gear-item-${p.key}'),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: on ? MgColors.surface : MgColors.well,
        borderRadius: BorderRadius.circular(MgRadius.button),
        border: Border.all(color: on ? MgColors.ink : MgColors.line, width: on ? 1.5 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          checked: on,
          label: '${p.label}, $price',
          excludeSemantics: true,
          onTap: () => onToggleItem(p.key, !on),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onToggleItem(p.key, !on),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: MgSize.touch),
              child: Row(children: [
                _box(on),
                const SizedBox(width: 12),
                Expanded(child: Text(p.label, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
                const SizedBox(width: 8),
                Text(price, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: on ? MgColors.link : MgColors.meta))),
              ]),
            ),
          ),
        ),
        if (on && list.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final z in list)
              gearSizeFree(state.avail, p.key, z)
                  ? BkSizeChip(
                      key: ValueKey('gear-size-${p.key}-$z'),
                      label: z,
                      selected: z == sz,
                      semanticLabel: '${p.label} $z',
                      onTap: () => ctrl.pickSize(p.key, z),
                    )
                  : GearSizeOutChipV2(key: ValueKey('gear-size-${p.key}-$z'), label: z, reason: tr.tr('groSizeOut')),
          ]),
          if (sz.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr.tr('groSizeChoose'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.warn)),
            ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }

  Widget _box(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: on ? MgColors.ink : MgColors.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: on ? MgColors.ink : MgColors.lineInput, width: 1.5),
        ),
        child: on ? Center(child: MgIcon(MgIcons.check, size: 16, color: MgColors.neon, stroke: 2.6)) : null,
      );
}

/// Tlačítko kompletu: název, popis, cena za den; stisknuté = tmavé.
class GearSetButtonV2 extends StatelessWidget {
  final GearPrice set;
  final bool on;
  final VoidCallback onTap;
  const GearSetButtonV2({super.key, required this.set, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final price = bkNb('${gearMoney(set.perDay)} ${tr.tr('groPerDay')}');
    return Semantics(
      button: true,
      toggled: on,
      label: '${set.label}, ${set.desc}, $price',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey('gear-set-${set.key}'),
          duration: MgMotion.of(context, MgMotion.color),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: on ? MgColors.ink : MgColors.surface,
            borderRadius: BorderRadius.circular(MgRadius.button),
            border: Border.all(color: on ? MgColors.ink : MgColors.lineInput, width: 1.5),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(set.label, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: on ? MgColors.onDark : MgColors.ink)),
                if (set.desc.isNotEmpty)
                  Text(set.desc, style: MgType.small.copyWith(color: on ? MgColors.onDarkLead : MgColors.lead)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(price,
                style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: on ? MgColors.neon : MgColors.link))),
          ]),
        ),
      ),
    );
  }
}

/// Velikost, která v termínu není volná: vypnutý přeškrtnutý čip.
class GearSizeOutChipV2 extends StatelessWidget {
  final String label;
  final String reason;
  const GearSizeOutChipV2({super.key, required this.label, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: false,
      label: '$label — $reason',
      excludeSemantics: true,
      child: Tooltip(
        message: reason,
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: MgColors.well,
            borderRadius: BorderRadius.circular(MgRadius.action),
            border: Border.all(color: MgColors.line),
          ),
          // Jako BkSizeChip: Row(min) drží šířku čipu podle textu (alignment by ve Wrapu roztáhl čip na celý řádek).
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label,
                style: MgType.small.copyWith(
                    fontWeight: FontWeight.w700, color: MgColors.disabled, decoration: TextDecoration.lineThrough)),
          ]),
        ),
      ),
    );
  }
}
