import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'booking_v2_parts.dart';

/// v2 look of the passenger-gear size sheet (CB-03): light MgSheet, the
/// form's own size chips, "Z minula" T3, footer "Potvrdit velikosti" (+
/// red "Odebrat" when the extra is already chosen). [sizes] is the map the
/// old sheet prefilled; [onConfirm] / [onRemove] are the old sheet's own
/// actions (they build the same `SelectedExtra` list). Drag-down / ✕ =
/// cancel, nothing changes.
Future<void> showPassengerSizesSheetV2(
  BuildContext context, {
  required String title,
  required String? sub,
  required bool fromLast,
  required Map<String, String?> sizes,
  required Map<String, List<String>> options,
  required String Function(String key) labelOf,
  required ValueChanged<Map<String, String?>> onConfirm,
  VoidCallback? onRemove,
}) {
  final sel = ValueNotifier<Map<String, String?>>(Map.of(sizes));
  return showMgSheet<void>(
    context,
    title: title,
    builder: (_) => ValueListenableBuilder<Map<String, String?>>(
      valueListenable: sel,
      builder: (c, m, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (sub != null) Text(sub, style: MgType.small.copyWith(color: MgColors.meta)),
        if (fromLast) ...[
          const SizedBox(height: MgSpace.s12),
          MgStateBanner(tone: MgTone.ok, title: t(c).tr('v2UxCbFromLast'), text: t(c).tr('bkSizesFromLast')),
        ],
        for (final e in options.entries) ...[
          const SizedBox(height: MgSpace.s16),
          BkLabel(labelOf(e.key)),
          Wrap(spacing: MgSpace.s8, runSpacing: MgSpace.s8, children: [
            for (final s in e.value)
              BkSizeChip(
                label: s,
                selected: m[e.key] == s,
                semanticLabel: '${labelOf(e.key)} $s',
                // Same rule as the old chip: tapping the chosen size clears it.
                onTap: () => sel.value = {...m, e.key: m[e.key] == s ? null : s},
              ),
          ]),
        ],
      ]),
    ),
    footer: ValueListenableBuilder<Map<String, String?>>(
      valueListenable: sel,
      builder: (c, m, _) {
        final any = m.values.any((v) => v != null);
        return _SizesFooter(
          confirmLabel: t(c).tr('v2UxCbConfirmSizes'),
          hint: any ? null : t(c).tr('v2UxCbPickOneSize'),
          onConfirm: any
              ? () {
                  onConfirm(m);
                  Navigator.pop(c);
                }
              : null,
          onRemove: onRemove == null
              ? null
              : () {
                  onRemove();
                  Navigator.pop(c);
                },
        );
      },
    ),
  );
}

/// v2 look of the single-size sheet (boots): tapping a size picks it and
/// closes the sheet (as before); the last booking's size is shown as a
/// "Z minula" note, never preselected.
Future<void> showSingleSizeSheetV2(
  BuildContext context, {
  required String title,
  required String? sub,
  required List<String> sizes,
  required String? current,
  required String? last,
  required ValueChanged<String> onPick,
  VoidCallback? onRemove,
}) {
  return showMgSheet<void>(
    context,
    title: title,
    builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sub != null) ...[
        Text(sub, style: MgType.small.copyWith(color: MgColors.meta)),
        const SizedBox(height: MgSpace.s12),
      ],
      if (last != null && sizes.contains(last)) ...[
        MgStateBanner(
          tone: MgTone.ok,
          title: t(c).tr('v2UxCbFromLast'),
          text: t(c).trArgs('v2UxCbLastSize', {'size': last}),
        ),
        const SizedBox(height: MgSpace.s12),
      ],
      Wrap(spacing: MgSpace.s8, runSpacing: MgSpace.s8, children: [
        for (final s in sizes)
          BkSizeChip(
            label: s,
            selected: s == current,
            semanticLabel: s == last ? '$s, ${t(c).tr('bkSizeLastTag')}' : s,
            onTap: () {
              onPick(s);
              Navigator.pop(c);
            },
          ),
      ]),
    ]),
    footer: onRemove == null
        ? null
        : Builder(
            builder: (c) => _SizesFooter(
              onRemove: () {
                onRemove();
                Navigator.pop(c);
              },
            ),
          ),
  );
}

class _SizesFooter extends StatelessWidget {
  final String? confirmLabel;
  final String? hint;
  final VoidCallback? onConfirm;
  final VoidCallback? onRemove;
  const _SizesFooter({this.confirmLabel, this.hint, this.onConfirm, this.onRemove});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint != null) ...[
            MgWordFit(
              minScale: 0.85,
              child: Text(hint!,
                  textAlign: TextAlign.center,
                  style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.warn)),
            ),
            const SizedBox(height: MgSpace.s8),
          ],
          if (confirmLabel != null) MgBtnInk(label: confirmLabel!, onTap: onConfirm),
          if (onRemove != null)
            Center(child: MgBtnText(label: t(context).tr('removeBtn'), color: MgColors.err, onTap: onRemove)),
        ],
      );
}
