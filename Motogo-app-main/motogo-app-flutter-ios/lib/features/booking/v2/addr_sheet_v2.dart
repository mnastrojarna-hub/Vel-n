import 'package:flutter/material.dart';

import '../../../core/booking_address_carry.dart' show AddrQuick;
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart' show mgToneChipColors;
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 look of the pickup / return address sheet (`showAddrBottomSheet`,
/// V22 §6.4 + §2.4): light sheet with ✕ 44, `lineInput` field, suggestions
/// and quick options as white rows with `iconTileLight`, GPS / Mapa as
/// `btnGhostLight`, the distance / status as a tintOk / warn line and ONE
/// ink primary „Potvrdit adresu“. Pure look: every action is the old
/// sheet's closure (`_pick`, `_useGps`, `_openMap`, `_confirm`), state comes
/// from the old sheet (Android only, CLAUDE.md rule 6).
class AddrSheetV2View extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onSuggestion;

  /// Quick options (other side of the handover, profile) — shown only while
  /// nothing is typed / picked, exactly like the old sheet.
  final List<AddrQuick> quick;
  final bool showQuick;
  final ValueChanged<AddrQuick> onQuick;
  final VoidCallback onGps;
  final VoidCallback? onMap;

  /// Distance / status line of the old sheet (null = none).
  final String? status;
  final bool statusError;

  /// true = the line is a progress text („Počítám km…“), not a result.
  final bool statusPending;
  final bool saving;
  final VoidCallback onConfirm;

  const AddrSheetV2View({
    super.key,
    required this.title,
    required this.controller,
    required this.onChanged,
    required this.suggestions,
    required this.onSuggestion,
    required this.quick,
    required this.showQuick,
    required this.onQuick,
    required this.onGps,
    required this.onMap,
    required this.status,
    required this.statusError,
    required this.statusPending,
    required this.saving,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final quickRows = showQuick && suggestions.isEmpty ? quick : const <AddrQuick>[];
    return MgSheetFrame(
      title: title,
      footer: MgBtnInk(
        label: tr.tr('v2AddrConfirm'),
        icon: MgIcons.check,
        busy: saving,
        onTap: saving ? null : onConfirm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          autofocus: true,
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(
            context,
            hint: tr.tr('v2AddrHint'),
            // Center: the 48 px prefix slot must not stretch the 20 px icon.
            prefixIcon: const Center(
              widthFactor: 1,
              heightFactor: 1,
              child: MgIcon(MgIcons.search, size: 20, color: MgColors.meta),
            ),
          ),
        ),
        MgAnimatedSize(
          duration: MgMotion.sheet,
          curve: MgMotion.emphasized,
          alignment: Alignment.topCenter,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (suggestions.isNotEmpty)
              _RowList(children: [
                for (var i = 0; i < suggestions.length; i++)
                  _suggestionRow(suggestions[i], divider: i < suggestions.length - 1),
              ]),
            if (quickRows.isNotEmpty)
              _RowList(children: [
                for (var i = 0; i < quickRows.length; i++)
                  _AddrRow(
                    icon: MgIcons.home,
                    eyebrow: quickRows[i].label,
                    title: quickRows[i].line,
                    chevron: true,
                    divider: i < quickRows.length - 1,
                    semanticLabel: '${quickRows[i].label}: ${quickRows[i].line}',
                    onTap: () => onQuick(quickRows[i]),
                  ),
              ]),
          ]),
        ),
        const SizedBox(height: MgSpace.s12),
        Row(children: [
          Expanded(child: MgBtnGhostLight(label: 'GPS', icon: MgIcons.gps, onTap: onGps)),
          if (onMap != null) ...[
            const SizedBox(width: MgSpace.s8),
            Expanded(child: MgBtnGhostLight(label: tr.tr('map'), icon: MgIcons.map, onTap: onMap)),
          ],
        ]),
        MgAnimatedSize(
          duration: MgMotion.sheet,
          curve: MgMotion.emphasized,
          alignment: Alignment.topCenter,
          child: status == null ? const SizedBox(width: double.infinity) : _status(status!),
        ),
      ]),
    );
  }

  Widget _suggestionRow(Map<String, dynamic> s, {required bool divider}) {
    final label = s['label'] as String? ?? s['name'] as String? ?? '';
    final desc = s['location'] as String? ?? '';
    return _AddrRow(
      icon: MgIcons.pin,
      title: label,
      sub: desc.isEmpty ? null : desc,
      divider: divider,
      onTap: () => onSuggestion(s),
    );
  }

  Widget _status(String text) {
    final tone = statusError ? MgTone.warn : (statusPending ? MgTone.pending : MgTone.ok);
    final (bg, fg, border, icon) = mgToneChipColors(tone, false);
    return Padding(
      padding: const EdgeInsets.only(top: MgSpace.s10),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(MgRadius.action),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgIcon(tone == MgTone.ok ? MgIcons.route : icon, size: 18, color: fg),
            const SizedBox(width: MgSpace.s8),
            Expanded(child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg))),
          ]),
        ),
      ),
    );
  }
}

/// White grouped list (1 px `line`, r16) under the field.
class _RowList extends StatelessWidget {
  final List<Widget> children;
  const _RowList({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: MgSpace.s8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(MgRadius.card),
          border: Border.all(color: MgColors.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
}

/// One address row (min 56): icon tile, optional eyebrow, title, sub.
class _AddrRow extends StatelessWidget {
  final String icon;
  final String? eyebrow;
  final String title;
  final String? sub;
  final bool chevron;
  final bool divider;
  final String? semanticLabel;
  final VoidCallback onTap;
  const _AddrRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.eyebrow,
    this.sub,
    this.chevron = false,
    this.divider = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: MgSpace.s8),
      decoration: divider ? const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))) : null,
      child: Row(children: [
        MgIconTileLight(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (eyebrow != null)
              Text(eyebrow!, style: MgType.meta.copyWith(color: MgColors.link)),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
            if (sub != null)
              Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(color: MgColors.meta)),
          ]),
        ),
        if (chevron) ...[
          const SizedBox(width: 4),
          const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.meta),
        ],
      ]),
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(MgRadius.action), child: row),
    );
  }
}
