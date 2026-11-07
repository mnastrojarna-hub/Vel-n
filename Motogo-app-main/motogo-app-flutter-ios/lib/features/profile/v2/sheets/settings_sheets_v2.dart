import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';
import '../../../../core/v2/widgets/mg_sheet.dart';

/// v2 look of "Změna hesla" (V21 P6c): two light inputs, the error inline,
/// pinned button with a spinner while saving. Validation + save stay in
/// `showChangePasswordSheet` ([onSubmit]).
class PasswordSheetV2View extends StatelessWidget {
  final TextEditingController pass;
  final TextEditingController confirm;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onClose;
  const PasswordSheetV2View({
    super.key,
    required this.pass,
    required this.confirm,
    required this.busy,
    required this.error,
    required this.onSubmit,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgSheetFrame(
      title: tr.tr('changePassword'),
      onClose: onClose,
      footer: MgBtnInk(
        label: tr.tr('changePasswordBtn'),
        icon: MgIcons.key,
        neonLabel: true,
        busy: busy,
        onTap: busy ? null : onSubmit,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: pass,
          obscureText: true,
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(context, label: tr.tr('newPasswordHint')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: confirm,
          obscureText: true,
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(context, label: tr.tr('confirmPasswordLabel')),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          MgShake(
            trigger: error,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const MgIcon(MgIcons.xCircle, size: 18, color: MgColors.err),
              const SizedBox(width: 8),
              Expanded(child: Text(error!, style: MgType.small.copyWith(color: MgColors.err))),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// One choice of the language / currency sheets.
class PfChoice {
  final String code;
  final String title;
  final String? sub;
  const PfChoice(this.code, this.title, [this.sub]);
}

/// v2 look of "Jazyk aplikace" / "Měna" (V21 P6d/P6e): light list rows with
/// a text code chip (no flag emoji), ✓ on the current one. [onPick] = the
/// existing closure (save, toast, `context.go('/')`).
class ChoiceSheetV2View extends StatelessWidget {
  final String title;
  final String? note;
  final List<PfChoice> items;
  final String current;
  final ValueChanged<int> onPick;
  final VoidCallback onClose;
  const ChoiceSheetV2View({
    super.key,
    required this.title,
    required this.items,
    required this.current,
    required this.onPick,
    required this.onClose,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return MgSheetFrame(
      title: title,
      onClose: onClose,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (note != null) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const MgIcon(MgIcons.info, size: 16, color: MgColors.meta),
            const SizedBox(width: 6),
            Expanded(child: Text(note!, style: MgType.small.copyWith(color: MgColors.lead))),
          ]),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, color: MgColors.line),
          _ChoiceRow(item: items[i], selected: items[i].code == current, onTap: () => onPick(i)),
        ],
      ]),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final PfChoice item;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceRow({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              Container(
                constraints: const BoxConstraints(minWidth: 44),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: selected ? MgColors.panel : MgColors.well,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? MgColors.panel : MgColors.line),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(item.code.toUpperCase(),
                      style: MgType.small.copyWith(
                          fontWeight: FontWeight.w900, color: selected ? MgColors.neon : MgColors.ink)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(item.title, style: MgType.title.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink)),
                  if (item.sub != null)
                    Text(item.sub!, style: MgType.tab(MgType.small.copyWith(color: MgColors.lead))),
                ]),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const MgPop(playOnMount: true, child: MgIcon(MgIcons.checkCircle, size: 22, color: MgColors.link)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
