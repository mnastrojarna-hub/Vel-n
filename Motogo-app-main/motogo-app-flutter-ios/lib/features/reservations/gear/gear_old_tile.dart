import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Dlaždice velikosti / kusu v úpravě výpůjčky výbavy (starý vzhled) —
/// stejný tvar jako velikosti objednávky výbavy (`gear_order_items.dart`):
/// světle zelená, vybraná tmavě zelená, vyprodaná šedá přeškrtnutá.
/// [danger] = výběr kusu k odebrání (vybraný červeně).
class GearOldTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final bool danger;
  final String? tooltip;
  final VoidCallback? onTap;

  const GearOldTile({
    super.key,
    required this.label,
    required this.selected,
    this.enabled = true,
    this.danger = false,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = !enabled
        ? MotoGoColors.g100
        : selected
            ? (danger ? MotoGoColors.red : MotoGoColors.greenDarker)
            : (danger ? MotoGoColors.redBg : MotoGoColors.greenPale);
    final Color fg = !enabled ? MotoGoColors.g400 : (selected ? Colors.white : MotoGoColors.black);
    final tile = Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: tooltip == null ? label : '$label — $tooltip',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minWidth: 46, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                color: fg,
                decoration: enabled ? TextDecoration.none : TextDecoration.lineThrough,
              )),
        ),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip!, child: tile);
  }
}
