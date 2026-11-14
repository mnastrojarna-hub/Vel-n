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
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../booking/booking_quote.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../moto_model.dart';
import '../catalog_fit.dart';
import '../catalog_text.dart';
import 'calc_state.dart';
import 'calc_step_moto_v2.dart';

/// "Volné v tvém termínu: n" (calculator without a bike, dates chosen):
/// ≤ 6 rows (thumb, name, branch · category, the bike's total "Tvoje
/// cena" beside — or, when a name word would not fit, under — the name) —
/// tapping a row picks that bike in the calculator; the rest goes to the
/// Motorky list with the same dates ([onShowAll]).
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
              // One layout for all rows: when the longest word of any name
              // ("Adventure", "Supermoto") would not fit beside its price
              // (narrow phone / large text), every price goes under its name
              // instead of splitting a word.
              LayoutBuilder(builder: (context, c) {
                final totals = [for (final m in shown) _freeTotal(m, st, loyalty)];
                var stacked = false;
                for (var i = 0; i < shown.length; i++) {
                  if (_needsStack(context, tr, shown[i], totals[i], c.maxWidth)) stacked = true;
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < shown.length; i++)
                    MgReveal(index: i, child: _FreeRow(moto: shown[i], total: totals[i], stacked: stacked)),
                ]);
              }),
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

/// The bike's total for the range — standard pickup price (the 12:00
/// saving is info on the bike's total); null = no price list.
double? _freeTotal(Motorcycle m, CalcState st, LoyaltyStatus? loyalty) =>
    m.prices != null && (m.prices?.cheapest ?? 0) > 0 ? quoteFor(m, st.start!, st.end!, loyalty: loyalty).total : null;

/// The row [width] cannot hold the longest word of the name / meta beside
/// the price column (thumb 54 + 10, chevron 4 + 20, gap 8).
bool _needsStack(BuildContext context, AppTranslations tr, Motorcycle m, double? total, double width) {
  if (total == null) return false;
  final base = DefaultTextStyle.of(context).style;
  final priceW = [
    catLineWidth(context, tr.tr('v2YourPrice'), base.merge(MgType.meta)),
    catLineWidth(context, catMoney(total), base.merge(MgType.tab(MgType.title))),
  ].reduce((a, b) => a > b ? a : b);
  final word = [
    catWordWidth(context, m.model, base.merge(MgType.title)),
    catWordWidth(context, calcMeta(tr, m), base.merge(MgType.meta)),
  ].reduce((a, b) => a > b ? a : b);
  return word > width - 54 - 10 - 4 - 20 - 8 - priceW;
}

class _FreeRow extends ConsumerWidget {
  final Motorcycle moto;
  final double? total;
  final bool stacked;
  const _FreeRow({required this.moto, required this.total, required this.stacked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final total = this.total;
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
          child: Builder(builder: (context) {
            Widget price(CrossAxisAlignment a) => Column(crossAxisAlignment: a, children: [
                  Text(tr.tr('v2YourPrice'), style: MgType.meta.copyWith(color: MgColors.meta)),
                  Text(catMoney(total!), style: MgType.tab(MgType.title.copyWith(color: MgColors.price))),
                ]);
            return Row(children: [
              CalcThumb(moto: moto, width: 54, height: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgWordFit(child: Text(moto.model, style: MgType.title.copyWith(color: MgColors.ink))),
                  Text(calcMeta(tr, moto), style: MgType.meta.copyWith(color: MgColors.meta)),
                  if (stacked && total != null) ...[const SizedBox(height: 4), price(CrossAxisAlignment.start)],
                ]),
              ),
              if (total != null && !stacked) ...[
                const SizedBox(width: 8),
                price(CrossAxisAlignment.end),
              ],
              const SizedBox(width: 4),
              MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.meta),
            ]);
          }),
        ),
      ),
    );
  }
}
