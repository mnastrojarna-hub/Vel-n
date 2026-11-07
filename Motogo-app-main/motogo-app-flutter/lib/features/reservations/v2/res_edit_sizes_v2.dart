import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/v2/booking_v2_parts.dart' show BkSizeChip;

/// The gear's v2 line icon for the old picker's Material icon.
String editGearIconV2(IconData icon) {
  if (icon == Icons.sports_motorsports) return MgIcons.helmet;
  if (icon == Icons.checkroom) return MgIcons.jacket;
  if (icon == Icons.straighten) return MgIcons.pants;
  return MgIcons.ruler;
}

/// v2 look of `EditGearSizePicker` (free gear sizes in the edit): white
/// card (chosen = tint), gear icon + label, "Zvoleno: M" + "ZDARMA", the
/// booking size chips. Same rule: tapping the chosen size clears it
/// ([onSizeSelected] null), any other picks it.
class EditGearSizePickerV2 extends StatelessWidget {
  final String label;
  final String icon;
  final List<String> sizes;
  final String? selectedSize;
  final ValueChanged<String?> onSizeSelected;
  const EditGearSizePickerV2({
    super.key,
    required this.label,
    required this.icon,
    required this.sizes,
    required this.selectedSize,
    required this.onSizeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final sel = selectedSize;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sel != null ? MgColors.tintOk : MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.card),
        border: Border.all(color: sel != null ? MgColors.tintOkBorder : MgColors.line, width: sel != null ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            MgIcon(icon, size: 18, color: sel != null ? MgColors.onTintOk : MgColors.link),
            const SizedBox(width: 8),
            Flexible(
              child: MgWordFit(
                child: Text(label, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
              ),
            ),
          ]),
          if (sel != null)
            Text(tr.trArgs('chosenSize', {'size': sel}),
                style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk)),
          Text(tr.tr('gearFree').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.link)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: MgSpace.s8, runSpacing: MgSpace.s8, children: [
          for (final s in sizes)
            BkSizeChip(
              label: s,
              selected: sel == s,
              semanticLabel: '$label $s',
              onTap: () => onSizeSelected(sel == s ? null : s),
            ),
        ]),
      ]),
    );
  }
}

/// v2 look of the edit passenger-gear sheet: light MgSheet (✕, drag-down),
/// the three free sizes as above — each tap writes AT ONCE through the
/// same callbacks (as the old sheet) — footer "Hotovo" (= close) and
/// "Odebrat doplněk" (= the old sheet's remove: clears the extra + sizes).
Future<void> showEditPassengerSheetV2(
  BuildContext context, {
  required String title,
  required List<(String label, String icon, List<String> sizes, String? size, ValueChanged<String?> onPick)> rows,
  required VoidCallback onRemove,
}) {
  final picked = <int, String?>{for (var i = 0; i < rows.length; i++) i: rows[i].$4};
  return showMgSheet<void>(
    context,
    title: title,
    builder: (_) => StatefulBuilder(
      builder: (c, setModal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++)
          EditGearSizePickerV2(
            label: rows[i].$1,
            icon: rows[i].$2,
            sizes: rows[i].$3,
            selectedSize: picked[i],
            onSizeSelected: (s) {
              setModal(() => picked[i] = s);
              rows[i].$5(s);
            },
          ),
      ]),
    ),
    footer: Builder(
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgBtnInk(label: t(c).tr('doneLabel'), neonLabel: true, onTap: () => Navigator.pop(c)),
        const SizedBox(height: 4),
        Center(
          child: MgBtnText(
            label: t(c).tr('removeAddon'),
            icon: MgIcons.trash,
            onTap: () {
              onRemove();
              Navigator.pop(c);
            },
          ),
        ),
      ]),
    ),
  );
}
