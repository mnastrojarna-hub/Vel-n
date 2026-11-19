import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../booking/booking_ui_helpers.dart' show bookingCard;
import '../gear_contract.dart';
import '../gear_order_state.dart';
import '../gear_order_ui.dart';
import '../gear_quote.dart';
import 'gear_order_branch.dart' show GearOldNote;

/// Krok 3 (starý vzhled): komplety, kusy se zaškrtnutím a cenou za den,
/// velikosti vybraného kusu (obsazené přeškrtnuté a vypnuté).
class GearOrderItems extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  final void Function(String key, bool on) onToggleItem;
  final void Function(String key) onToggleSet;
  const GearOrderItems({super.key, required this.state, required this.ctrl, required this.onToggleItem, required this.onToggleSet});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final prices = state.prices;
    return bookingCard(
      3,
      tr.tr('groStepGear'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GearOldNote(tr.tr('groGearHint')),
        const SizedBox(height: 6),
        for (final s in gearSetsOf(prices)) _set(tr, s, gearSetOn(s, prices, state.sel)),
        for (final m in state.drops) GearOldNote(m.text(tr), key: const ValueKey('gear-size-dropped'), warn: true),
        for (final p in gearItemsOf(prices)) _item(tr, p),
        if (state.isSelf) GearOldNote(tr.tr('groSsCapNote')),
      ]),
    );
  }

  Widget _set(AppTranslations tr, GearPrice s, bool on) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          key: ValueKey('gear-set-${s.key}'),
          onTap: () => onToggleSet(s.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: on ? MotoGoColors.greenPale : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? MotoGoColors.green : MotoGoColors.g200, width: on ? 2 : 1),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                  if (s.desc.isNotEmpty) Text(s.desc, style: const TextStyle(fontSize: 11, color: MotoGoColors.g600)),
                ]),
              ),
              Text('${gearMoney(s.perDay)} ${tr.tr('groPerDay')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
            ]),
          ),
        ),
      );

  Widget _item(AppTranslations tr, GearPrice p) {
    final on = state.sel.containsKey(p.key);
    final sz = state.sel[p.key] ?? '';
    final list = gearSizesFor(p, state.isSelf);
    return Padding(
      key: ValueKey('gear-item-${p.key}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onToggleItem(p.key, !on),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: on ? MotoGoColors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: on ? MotoGoColors.green : MotoGoColors.g200, width: 2),
                ),
                child: on ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(p.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black))),
              Text('${gearMoney(p.perDay)} ${tr.tr('groPerDay')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g600)),
            ]),
          ),
        ),
        if (on && list.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final z in list) _chip(tr, p, z, z == sz)]),
          if (sz.isEmpty) GearOldNote(tr.tr('groSizeChoose'), warn: true),
        ],
      ]),
    );
  }

  Widget _chip(AppTranslations tr, GearPrice p, String z, bool a) {
    final ok = gearSizeFree(state.avail, p.key, z);
    final chip = Semantics(
      button: true,
      enabled: ok,
      selected: a,
      label: ok ? '${p.label} $z' : '$z — ${tr.tr('groSizeOut')}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('gear-size-${p.key}-$z'),
        onTap: ok ? () => ctrl.pickSize(p.key, z) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minWidth: 46),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: !ok ? MotoGoColors.g100 : (a ? MotoGoColors.greenDarker : MotoGoColors.greenPale),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(z,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: a ? FontWeight.w900 : FontWeight.w600,
                color: !ok ? MotoGoColors.g400 : (a ? Colors.white : MotoGoColors.black),
                decoration: ok ? TextDecoration.none : TextDecoration.lineThrough,
              )),
        ),
      ),
    );
    return ok ? chip : Tooltip(message: tr.tr('groSizeOut'), child: chip);
  }
}
