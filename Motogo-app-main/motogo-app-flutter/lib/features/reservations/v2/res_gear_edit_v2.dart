import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../gear/gear_edit_view.dart';
import '../gear/gear_note.dart';
import 'res_gear_sizes_v2.dart';
import 'res_status_v2.dart';

/// Úprava výpůjčky výbavy ve v2 vzhledu (stav a akce drží
/// `GearEditScreen`): tmavá kompaktní hlavička, souhrn kusů, Velikosti,
/// Odebrat kus, Termín na webu, přidání kusu přes kontakt, storno.
class ResGearEditV2 extends StatelessWidget {
  final GearEditData data;
  final GearEditActions actions;
  const ResGearEditV2({super.key, required this.data, required this.actions});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final d = data;
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: w);
    return MgPage(
      header: MgAppBar(title: d.title, subtitle: d.subtitle, onBack: actions.onBack),
      overlapHero: false,
      sections: [
        pad(MgCard(
          child: Row(children: [
            const SizedBox(width: 56, height: 56, child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(12)), child: ResGearPhoto())),
            const SizedBox(width: 12),
            Expanded(child: Text(d.summary, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
          ]),
        )),
        if (d.done != null) pad(GearNoteBox(key: const ValueKey('gear-edit-done'), tone: MgTone.ok, text: d.done!)),
        if (d.error != null) pad(GearNoteBox(key: const ValueKey('gear-edit-error'), tone: MgTone.err, text: d.error!)),
        if (d.closedNote != null) pad(GearNoteBox(text: d.closedNote!)),
        if (d.sizes != null) pad(ResGearSizesV2(data: d, actions: actions)),
        if (d.removeItems != null) pad(_remove(context, tr)),
        if (d.datesWeb)
          pad(MgCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MgBtnGhostLight(
                key: const ValueKey('gear-edit-dates-web'),
                label: tr.tr('gearEditDatesWeb'),
                icon: MgIcons.external,
                onTap: actions.onDatesWeb,
              ),
              const SizedBox(height: 8),
              Text(tr.tr('gearEditDatesWebHint'), style: MgType.small.copyWith(color: MgColors.lead)),
            ]),
          )),
        if (d.datesWeb) pad(GearNoteBox(text: tr.tr('gearAddItemContact'))),
        if (d.canCancel)
          pad(MgBtnDestructive(
            key: const ValueKey('gear-edit-cancel'),
            label: tr.tr('cancelReservationBtn'),
            onTap: actions.onCancel,
          )),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _remove(BuildContext context, AppTranslations tr) {
    final d = data;
    return MgCard(
      key: const ValueKey('gear-remove-v2'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr.tr('gearRemoveTitle'), style: MgType.title.copyWith(color: MgColors.ink)),
        const SizedBox(height: 4),
        Text(tr.tr('gearRemoveIntro'), style: MgType.small.copyWith(color: MgColors.lead)),
        const SizedBox(height: 12),
        for (final i in d.removeItems!)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RemoveRow(
              key: ValueKey('gear-remove-${i.key}'),
              icon: ResGearSizesV2.gearIcon(i.key),
              label: i.size.isEmpty ? i.label : '${i.label} · ${i.size}',
              selected: d.removePick == i.key,
              onTap: d.busy ? null : () => actions.onChooseRemove(i.key),
            ),
          ),
        const SizedBox(height: 4),
        if (d.removeText == null)
          const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link)))
        else
          Text(d.removeText!, style: MgType.small.copyWith(color: MgColors.ink, fontWeight: FontWeight.w600)),
        if (d.removeOk && d.removePick != null) ...[
          const SizedBox(height: 12),
          MgBtnDestructive(
            key: const ValueKey('gear-remove-cta'),
            label: tr.tr('gearRemoveCta'),
            busy: d.busy,
            onTap: d.busy ? null : actions.onRemove,
          ),
        ],
        const SizedBox(height: 10),
        Text(tr.tr('gearRemoveLastNote'), style: MgType.small.copyWith(color: MgColors.meta)),
      ]),
    );
  }
}

class _RemoveRow extends StatelessWidget {
  final String icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _RemoveRow({super.key, required this.icon, required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? MgColors.sos.withValues(alpha: 0.08) : MgColors.well,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? MgColors.sos : MgColors.line, width: selected ? 1.5 : 1),
            ),
            child: Row(children: [
              MgIcon(icon, size: 18, color: selected ? MgColors.sos : MgColors.link),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink))),
              if (selected) const MgIcon(MgIcons.checkCircle, size: 18, color: MgColors.sos),
            ]),
          ),
        ),
      );
}
