import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/widgets/mg_nav_controls.dart';
import '../widgets/res_detail_button.dart';
import '../widgets/res_detail_card.dart';
import 'gear_note.dart';
import 'gear_old_tile.dart';

/// Data a akce obrazovky úprav výpůjčky výbavy — stav drží
/// `GearEditScreen`, vzhled kreslí [GearEditOldView] / `ResGearEditV2`.

class GearSizeRowData {
  final String key;
  final String label;
  final List<String> sizes;
  final Set<String> soldOut;
  final String selected;
  final String orig;
  const GearSizeRowData({
    required this.key,
    required this.label,
    required this.sizes,
    required this.soldOut,
    required this.selected,
    required this.orig,
  });
}

class GearRemoveItemData {
  final String key;
  final String label;
  final String size;
  const GearRemoveItemData({required this.key, required this.label, required this.size});
}

class GearEditData {
  final String title;
  final String subtitle;
  final String summary;
  final String? done;
  final String? error;
  final bool busy;
  /// Nic upravit nejde (nezaplacená / převzatá / skončená) — proč.
  final String? closedNote;
  /// null = sekce Velikosti se nenabízí.
  final List<GearSizeRowData>? sizes;
  final bool selfService;
  final bool sizesChanged;
  /// null = sekce Odebrat kus se nenabízí.
  final List<GearRemoveItemData>? removeItems;
  final String? removePick;
  /// Náhled vratky / výzva; null = načítá se.
  final String? removeText;
  final bool removeOk;
  final bool datesWeb;
  final bool canCancel;

  const GearEditData({
    required this.title,
    required this.subtitle,
    required this.summary,
    this.done,
    this.error,
    this.busy = false,
    this.closedNote,
    this.sizes,
    this.selfService = false,
    this.sizesChanged = false,
    this.removeItems,
    this.removePick,
    this.removeText,
    this.removeOk = false,
    this.datesWeb = false,
    this.canCancel = false,
  });
}

class GearEditActions {
  final VoidCallback onBack;
  final void Function(String key, String size) onPickSize;
  final VoidCallback onSaveSizes;
  final ValueChanged<String> onChooseRemove;
  final VoidCallback onRemove;
  final VoidCallback onDatesWeb;
  final VoidCallback onCancel;
  const GearEditActions({
    required this.onBack,
    required this.onPickSize,
    required this.onSaveSizes,
    required this.onChooseRemove,
    required this.onRemove,
    required this.onDatesWeb,
    required this.onCancel,
  });
}

/// Starý vzhled (stejný jazyk jako detail rezervace: tmavá hlavička,
/// bílé karty, zelená / červená tlačítka).
class GearEditOldView extends StatelessWidget {
  final GearEditData data;
  final GearEditActions actions;
  const GearEditOldView({super.key, required this.data, required this.actions});

  static const _h = TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black);
  static const _p = TextStyle(fontSize: 12, color: MotoGoColors.g600, height: 1.4);

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final d = data;
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 14),
            decoration: const BoxDecoration(
              color: MotoGoColors.dark,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(children: [
              MgBackTap(
                onTap: actions.onBack,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                  child: const Center(
                    child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(d.subtitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ]),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          sliver: SliverList.list(children: [
            ResDetailCard(children: [Text(d.summary, style: _h)]),
            const SizedBox(height: 12),
            if (d.done != null) GearNoteBox(key: const ValueKey('gear-edit-done'), tone: MgTone.ok, text: d.done!),
            if (d.error != null) GearNoteBox(key: const ValueKey('gear-edit-error'), tone: MgTone.err, text: d.error!),
            if (d.closedNote != null) GearNoteBox(text: d.closedNote!),
            if (d.sizes != null) ...[_sizes(context, tr, d.sizes!), const SizedBox(height: 12)],
            if (d.removeItems != null) ...[_remove(tr, d.removeItems!), const SizedBox(height: 12)],
            if (d.datesWeb) ...[
              ResDetailCard(children: [
                ResDetailButton.outlined(
                  key: const ValueKey('gear-edit-dates-web'),
                  emoji: '📅',
                  label: tr.tr('gearEditDatesWeb'),
                  onTap: actions.onDatesWeb,
                ),
                const SizedBox(height: 8),
                Text(tr.tr('gearEditDatesWebHint'), style: _p),
              ]),
              const SizedBox(height: 12),
            ],
            if (d.datesWeb) GearNoteBox(text: tr.tr('gearAddItemContact')),
            if (d.canCancel)
              ResDetailButton.danger(
                key: const ValueKey('gear-edit-cancel'),
                emoji: '🗑️',
                label: tr.tr('cancelReservationBtn'),
                onTap: actions.onCancel,
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _sizes(BuildContext context, AppTranslations tr, List<GearSizeRowData> rows) {
    return ResDetailCard(children: [
      Text(tr.tr('gearSizesTitle'), style: _h),
      const SizedBox(height: 4),
      Text(tr.tr('gearSizesIntro'), style: _p),
      if (data.selfService) ...[const SizedBox(height: 4), Text('ⓘ ${tr.tr('gearSsLimits')}', style: _p)],
      const SizedBox(height: 10),
      for (final r in rows) ...[
        Text(r.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in r.sizes)
            GearOldTile(
              key: ValueKey('gear-size-${r.key}-$s'),
              label: s,
              selected: r.selected == s,
              enabled: !r.soldOut.contains(s),
              tooltip: r.soldOut.contains(s) ? tr.tr('gearSoldOut') : null,
              onTap: data.busy ? null : () => actions.onPickSize(r.key, s),
            ),
        ]),
        const SizedBox(height: 10),
      ],
      Text(data.sizesChanged ? tr.tr('gearSizesFree') : tr.tr('gearSizesPick'), style: _p),
      const SizedBox(height: 10),
      // Bez změny šedé a neaktivní (dřív svítilo zeleně a nic nedělalo).
      IgnorePointer(
        ignoring: !data.sizesChanged || data.busy,
        child: Opacity(
          opacity: data.sizesChanged ? 1 : 0.45,
          child: ResDetailButton.primary(
            key: const ValueKey('gear-sizes-save'),
            emoji: '✓',
            label: tr.tr('gearSizesSave'),
            onTap: data.sizesChanged && !data.busy ? actions.onSaveSizes : () {},
          ),
        ),
      ),
    ]);
  }

  Widget _remove(AppTranslations tr, List<GearRemoveItemData> items) {
    return ResDetailCard(children: [
      Text(tr.tr('gearRemoveTitle'), style: _h),
      const SizedBox(height: 4),
      Text(tr.tr('gearRemoveIntro'), style: _p),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final i in items)
          GearOldTile(
            key: ValueKey('gear-remove-${i.key}'),
            label: i.size.isEmpty ? i.label : '${i.label} ${i.size}',
            selected: data.removePick == i.key,
            danger: true,
            onTap: data.busy ? null : () => actions.onChooseRemove(i.key),
          ),
      ]),
      const SizedBox(height: 10),
      if (data.removeText == null)
        const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
      else
        Text(data.removeText!, style: _p),
      const SizedBox(height: 10),
      if (data.removeOk && data.removePick != null)
        ResDetailButton.danger(
          key: const ValueKey('gear-remove-cta'),
          emoji: '➖',
          label: tr.tr('gearRemoveCta'),
          onTap: data.busy ? () {} : actions.onRemove,
        ),
      const SizedBox(height: 8),
      Text(tr.tr('gearRemoveLastNote'), style: _p),
    ]);
  }
}
