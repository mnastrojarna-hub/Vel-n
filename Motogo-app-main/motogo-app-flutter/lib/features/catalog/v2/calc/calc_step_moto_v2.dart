import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_anim_loops.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_sheet.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../catalog_provider.dart' show filteredMotoIdsProvider;
import '../../moto_model.dart';
import '../catalog_text.dart';
import 'calc_state.dart';

/// Step ② of the calculator: a 54 px picker field (never a native select)
/// opening a light sheet list, and the selected bike card (photo, name,
/// branch · category, rank "od" price + struck list price, status, "Detail
/// motorky ›" → the existing `/moto/:id`).
class CalcStepMotoV2 extends ConsumerWidget {
  final List<Motorcycle> offered;
  final Motorcycle? selected;
  const CalcStepMotoV2({super.key, required this.offered, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final pct = ref.watch(loyaltyStatusProvider).valueOrNull?.percent ?? 0;
    final m = selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        label: '${tr.tr('v2CalcStepMoto')}: ${m?.model ?? tr.tr('v2CalcMotoAny')}',
        excludeSemantics: true,
        onTap: () => _openPicker(context, ref),
        child: MgPress(
          onTap: () => _openPicker(context, ref),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MgColors.lineInput, width: 1.5),
            ),
            child: Row(children: [
              MgIcon(MgIcons.moto, size: 22, color: MgColors.link),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m?.model ?? tr.tr('v2CalcMotoAny'),
                    style: MgType.title.copyWith(color: m == null ? MgColors.lead : MgColors.ink)),
              ),
              MgIcon(MgIcons.chevronDown, size: 20, color: MgColors.meta),
            ]),
          ),
        ),
      ),
      if (m != null) ...[
        const SizedBox(height: 12),
        MgEnter(trigger: m.id, child: _SelectedMoto(moto: m, pct: pct, siblings: [for (final o in offered) o.id])),
      ],
    ]);
  }

  void _openPicker(BuildContext context, WidgetRef ref) {
    showMgSheet<void>(
      context,
      title: t(context).tr('v2CalcStepMoto'),
      builder: (ctx) => _PickerList(offered: offered, selectedId: selected?.id),
    );
  }
}

class _SelectedMoto extends ConsumerWidget {
  final Motorcycle moto;
  final int pct;

  /// The calculator's bikes — the detail pager swipes through them (like
  /// every other entry sets its shown list first).
  final List<String> siblings;
  const _SelectedMoto({required this.moto, required this.pct, required this.siblings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final st = calcStatus(tr, moto);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MgColors.well,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.line),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CalcThumb(moto: moto, width: 96, height: 64),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(moto.model, style: MgType.title.copyWith(color: MgColors.ink)),
            const SizedBox(height: 2),
            Text(calcMeta(tr, moto), style: MgType.small.copyWith(color: MgColors.meta)),
            const SizedBox(height: 4),
            CalcFromPrice(moto: moto, pct: pct),
            if (st != null) ...[
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                RepaintBoundary(
                  child: MgPing(size: 8, color: st.$2 ? MgColors.neonLo : MgColors.pending, active: st.$2),
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(st.$1, style: MgType.meta.copyWith(color: st.$2 ? MgColors.link : MgColors.warn))),
              ]),
            ],
            MgBtnText(
              label: '${tr.tr('v2CalcDetail')} ›',
              onTap: () {
                ref.read(filteredMotoIdsProvider.notifier).state =
                    siblings.contains(moto.id) ? siblings : [moto.id];
                context.push('/moto/${moto.id}');
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PickerList extends ConsumerWidget {
  final List<Motorcycle> offered;
  final String? selectedId;
  const _PickerList({required this.offered, required this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final pct = ref.watch(loyaltyStatusProvider).valueOrNull?.percent ?? 0;
    void pick(String? id) {
      ref.read(calcStateProvider.notifier).setMoto(id);
      Navigator.of(context).maybePop();
    }

    Widget row({required bool on, required VoidCallback onTap, required Widget child, required String label}) => Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: on ? MgColors.tintOk : MgColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? MgColors.tintOkBorder : MgColors.line, width: on ? 1.5 : 1),
              ),
              child: child,
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(
        on: selectedId == null,
        label: tr.tr('v2CalcMotoAny'),
        onTap: () => pick(null),
        child: Row(children: [
          MgIcon(MgIcons.moto, size: 22, color: MgColors.link),
          const SizedBox(width: 10),
          Expanded(child: Text(tr.tr('v2CalcMotoAny'), style: MgType.title.copyWith(color: MgColors.ink))),
          if (selectedId == null) MgIcon(MgIcons.check, size: 20, color: MgColors.link),
        ]),
      ),
      for (final m in offered) ...[
        const SizedBox(height: 8),
        row(
          on: m.id == selectedId,
          label: '${m.model}, ${calcMeta(tr, m)}',
          onTap: () => pick(m.id),
          child: Row(children: [
            CalcThumb(moto: m, width: 54, height: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.model, style: MgType.title.copyWith(color: MgColors.ink)),
                Text(calcMeta(tr, m), style: MgType.meta.copyWith(color: MgColors.meta)),
                CalcFromPrice(moto: m, pct: pct, small: true),
                if (calcStatus(tr, m) case final st?)
                  Text(st.$1, style: MgType.meta.copyWith(color: st.$2 ? MgColors.link : MgColors.warn)),
              ]),
            ),
            if (m.id == selectedId) MgIcon(MgIcons.check, size: 20, color: MgColors.link),
          ]),
        ),
      ],
    ]);
  }
}

/// "Mezná · Cestovní".
String calcMeta(AppTranslations tr, Motorcycle m) => [
      if ((m.branchName ?? m.branchCity) != null) (m.branchName ?? m.branchCity)!,
      if (m.category != null && m.category!.isNotEmpty) catCategoryLabel(tr, m.category!),
    ].join(' · ');

/// Status line from EXISTING bike fields: (text, positive). Service →
/// "V servisu…" (the calendar blocks the service days); free today → live.
(String, bool)? calcStatus(AppTranslations tr, Motorcycle m) {
  if (m.status == 'maintenance') return (tr.tr('v2CalcStMaint'), false);
  if (m.availableToday == true) return (tr.tr('v2CalcStToday'), true);
  return null;
}

class CalcThumb extends StatelessWidget {
  final Motorcycle moto;
  final double width;
  final double height;
  const CalcThumb({super.key, required this.moto, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final img = moto.displayImage;
    final fb = Center(child: MgIcon(MgIcons.moto, size: 24, color: MgColors.onDarkFloor));
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height,
        color: MgColors.night,
        child: img.isEmpty ? fb : MgImage(img, thumbWidth: 240, fit: BoxFit.cover, error: fb),
      ),
    );
  }
}

/// "Tvoje cena od 2 727 Kč/den" + struck list "2 811 Kč".
class CalcFromPrice extends StatelessWidget {
  final Motorcycle moto;
  final int pct;
  final bool small;
  const CalcFromPrice({super.key, required this.moto, required this.pct, this.small = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final cheapest = moto.prices?.cheapest ?? 0;
    if (cheapest <= 0) return const SizedBox.shrink();
    final from = catFromPerDay(moto, pct);
    final base = small ? MgType.meta : MgType.small;
    return Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.end, children: [
      Text(tr.trArgs('v2CalcFromPerDay', {'amount': catMoney(from)}),
          style: MgType.tab(base.copyWith(fontWeight: FontWeight.w800, color: MgColors.price))),
      if (pct > 0 && from < cheapest)
        Text(catMoney(cheapest),
            style: MgType.tab(base.copyWith(fontWeight: FontWeight.w600, color: MgColors.meta, decoration: TextDecoration.lineThrough))),
    ]);
  }
}
