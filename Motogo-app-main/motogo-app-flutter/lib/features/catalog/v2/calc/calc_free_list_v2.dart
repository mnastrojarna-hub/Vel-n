import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_skeleton.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../booking/booking_quote.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../moto_model.dart';
import '../catalog_text.dart';
import 'calc_state.dart';
import 'calc_step_moto_v2.dart';

/// "Volné v tvém termínu: n" (calculator without a bike, dates chosen):
/// ≤ 6 rows (thumb, name, branch · category, the bike's total "Tvoje
/// cena") — tapping a row picks that bike in the calculator; the rest goes
/// to the Motorky list with the same dates ([onShowAll]).
class CalcFreeListV2 extends ConsumerWidget {
  final CalcState st;
  final VoidCallback onShowAll;
  const CalcFreeListV2({super.key, required this.st, required this.onShowAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final key = (st.branchId, st.start!, st.end!);
    final async = ref.watch(calcFreeMotosProvider(key));
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    return MgCard(
      child: async.when(
        skipLoadingOnReload: true,
        loading: () => Column(children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            const Row(children: [
              MgSkeleton(width: 54, height: 40, radius: 10),
              SizedBox(width: 10),
              Expanded(child: MgSkeleton(height: 14)),
            ]),
          ],
        ]),
        error: (e, _) => MgErrorView(
          error: e,
          what: tr.tr('fxMotosLoadFail'),
          onRetry: () => ref.invalidate(calcFreeMotosProvider(key)),
        ),
        data: (free) {
          // Kids' bikes last (as the web), otherwise the fleet order.
          final list = [...free.where((m) => m.category != 'detske'), ...free.where((m) => m.category == 'detske')];
          final shown = list.take(6).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr.trArgs('v2CalcFreeTitle', {'n': free.length}), style: MgType.section.copyWith(color: MgColors.ink)),
            const SizedBox(height: 10),
            if (free.isEmpty)
              Text(tr.tr('v2CalcFreeNone'), style: MgType.body.copyWith(color: MgColors.body2))
            else
              for (var i = 0; i < shown.length; i++)
                MgReveal(index: i, child: _FreeRow(moto: shown[i], st: st, loyalty: loyalty)),
            if (list.length > 6)
              Align(
                alignment: Alignment.centerLeft,
                child: MgBtnText(
                  label: '${tr.trArgs('v2CalcFreeMore', {'n': list.length - 6})} ›',
                  onTap: onShowAll,
                ),
              ),
            const SizedBox(height: 8),
            MgBtnInk(label: tr.tr('v2CalcShowFree'), icon: MgIcons.moto, neonLabel: true, onTap: onShowAll),
          ]);
        },
      ),
    );
  }
}

class _FreeRow extends ConsumerWidget {
  final Motorcycle moto;
  final CalcState st;
  final LoyaltyStatus? loyalty;
  const _FreeRow({required this.moto, required this.st, required this.loyalty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final has = moto.prices != null && (moto.prices?.cheapest ?? 0) > 0;
    // Standard pickup price (the 12:00 saving is info on the bike's total).
    final total = has ? quoteFor(moto, st.start!, st.end!, loyalty: loyalty).total : null;
    return Semantics(
      button: true,
      label: '${moto.model}, ${calcMeta(tr, moto)}${total == null ? '' : ', ${catMoney(total)}'}',
      excludeSemantics: true,
      onTap: () => ref.read(calcStateProvider.notifier).setMoto(moto.id),
      child: InkWell(
        onTap: () => ref.read(calcStateProvider.notifier).setMoto(moto.id),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))),
          child: Row(children: [
            CalcThumb(moto: moto, width: 54, height: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(moto.model, style: MgType.title.copyWith(color: MgColors.ink)),
                Text(calcMeta(tr, moto), style: MgType.meta.copyWith(color: MgColors.meta)),
              ]),
            ),
            if (total != null) ...[
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(tr.tr('v2YourPrice'), style: MgType.meta.copyWith(color: MgColors.meta)),
                Text(catMoney(total), style: MgType.tab(MgType.title.copyWith(color: MgColors.price))),
              ]),
            ],
            const SizedBox(width: 4),
            MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.meta),
          ]),
        ),
      ),
    );
  }
}
